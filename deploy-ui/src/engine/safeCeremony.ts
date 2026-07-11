import type Safe from '@safe-global/protocol-kit'
import type SafeApiKit from '@safe-global/api-kit'
import {
  OperationType,
  type SafeMultisigTransactionResponse,
  type SafeTransaction,
} from '@safe-global/types-kit'
import { getAddress, type Address, type Hex } from 'viem'
import { CeremonyHaltError } from './planExecutor'
import { evaluatePredicate } from './predicates'
import {
  assertRunStateIds,
  receiptBlockNumber,
  type ProgressStore,
  type RunState,
} from './runState'
import type {
  BundleManifest,
  DeploymentPlan,
  ExpectedAddresses,
  ReadTransport,
  ReceiptLike,
} from './types'

type ProtocolKit = Pick<
  Safe,
  | 'createTransaction'
  | 'executeTransaction'
  | 'getAddress'
  | 'getOwners'
  | 'getSafeProvider'
  | 'getThreshold'
  | 'getTransactionHash'
  | 'signHash'
  | 'signTransaction'
>

type ApiKit = Pick<
  SafeApiKit,
  'confirmTransaction' | 'getTransaction' | 'proposeTransaction'
>

export interface SafeTransport extends ReadTransport {
  waitForReceipt(hash: Hex): Promise<ReceiptLike>
  getReceipt(hash: Hex): Promise<ReceiptLike | null>
}

export interface SignatureProgress {
  safeTxHash: Hex
  confirmations: number
  threshold: number
  executed: boolean
  executionTxHash: Hex | null
}

export interface SafeBundleResult {
  safeTxHash: Hex
  executionTxHash?: Hex
  progress: SignatureProgress
  runState: RunState
  predicateDetails: string[]
  direct: boolean
}

function asHex(value: string): Hex {
  if (!/^0x[a-fA-F0-9]+$/.test(value)) throw new Error(`Invalid hex value: ${value}`)
  return value as Hex
}

function sortManifests(manifests: BundleManifest[]): BundleManifest[] {
  return [...manifests].sort((left, right) => left.bundle.number - right.bundle.number)
}

export function validateBundleArtifacts(
  plan: DeploymentPlan,
  planHash: Hex,
  manifests: BundleManifest[],
  expectedAddresses: ExpectedAddresses,
): BundleManifest[] {
  if (manifests.length === 0) throw new Error('At least one bundle manifest is required.')
  const ordered = sortManifests(manifests)
  const seenPlanIds: string[] = []
  const safe = ordered[0].safe.address.toLowerCase()

  ordered.forEach((manifest, index) => {
    if (manifest.bundle.number !== index + 1) {
      throw new Error(`Bundle numbers must be contiguous from 1; found ${manifest.bundle.number}.`)
    }
    if (manifest.plan.fileHash.toLowerCase() !== planHash.toLowerCase()) {
      throw new Error(`Bundle ${manifest.bundle.number} plan hash does not match loaded plan bytes.`)
    }
    if (
      manifest.plan.chainId !== plan.chainId ||
      manifest.plan.network !== plan.network ||
      manifest.plan.release !== plan.release
    ) {
      throw new Error(`Bundle ${manifest.bundle.number} plan identity does not match loaded plan.`)
    }
    if (manifest.safe.address.toLowerCase() !== safe) {
      throw new Error('All manifests must target the same Safe.')
    }
    if (manifest.safe.address.toLowerCase() !== plan.expectedExecutor.toLowerCase()) {
      throw new Error(`Bundle Safe does not match plan expectedExecutor ${plan.expectedExecutor}.`)
    }
    if (manifest.safe.version !== '1.4.1') {
      throw new Error(`Bundle ${manifest.bundle.number} requires unsupported Safe ${manifest.safe.version}.`)
    }
    if (manifest.safeTransaction.operation !== 1) {
      throw new Error(`Bundle ${manifest.bundle.number} outer operation must be DELEGATECALL (1).`)
    }
    for (const entry of manifest.innerTransactions) {
      const planEntry = plan.transactions[entry.planIndex]
      if (!planEntry || planEntry.id !== entry.planId) {
        throw new Error(`Bundle ${manifest.bundle.number} contains an invalid plan index/id pair.`)
      }
      if (entry.kind === 'deploy') {
        const expected = expectedAddresses[entry.planId]
        if (!expected || !entry.precomputedAddress) {
          throw new Error(`${entry.planId}: missing precomputed deployment address.`)
        }
        if (expected.toLowerCase() !== entry.precomputedAddress.toLowerCase()) {
          throw new Error(`${entry.planId}: manifest and expected-addresses.json disagree.`)
        }
      }
      seenPlanIds.push(entry.planId)
    }
  })

  const planIds = plan.transactions.map((transaction) => transaction.id)
  if (JSON.stringify(seenPlanIds) !== JSON.stringify(planIds)) {
    throw new Error('Bundles must cover every plan entry exactly once and in plan order.')
  }
  const deployIds = new Set(
    plan.transactions.filter((transaction) => transaction.kind === 'deploy').map((entry) => entry.id),
  )
  for (const key of Object.keys(expectedAddresses)) {
    if (!deployIds.has(key)) throw new Error(`expected-addresses.json contains unknown deploy id ${key}.`)
  }
  return ordered
}

export class SafeCeremony {
  readonly manifests: BundleManifest[]

  constructor(
    readonly plan: DeploymentPlan,
    readonly planHash: Hex,
    manifests: BundleManifest[],
    readonly expectedAddresses: ExpectedAddresses,
    private readonly transport: SafeTransport,
    private readonly protocolKit: ProtocolKit,
    private readonly apiKit: ApiKit | null,
    private readonly store: ProgressStore,
  ) {
    this.manifests = validateBundleArtifacts(plan, planHash, manifests, expectedAddresses)
  }

  getRunState(): RunState {
    return this.store.load()
  }

  private async assertContext(): Promise<{
    safe: Address
    signer: Address
    threshold: number
  }> {
    const [chainId, safeValue, owners, signerValue, threshold] = await Promise.all([
      this.transport.getChainId(),
      this.protocolKit.getAddress(),
      this.protocolKit.getOwners(),
      this.protocolKit.getSafeProvider().getSignerAddress(),
      this.protocolKit.getThreshold(),
    ])
    if (chainId !== this.plan.chainId) {
      throw new CeremonyHaltError(
        `Chain mismatch: plan requires ${this.plan.chainId}, wallet is on ${chainId}.`,
      )
    }
    const safe = getAddress(safeValue)
    if (safe.toLowerCase() !== this.plan.expectedExecutor.toLowerCase()) {
      throw new CeremonyHaltError(
        `Safe mismatch: plan requires ${this.plan.expectedExecutor}, protocol kit loaded ${safe}.`,
      )
    }
    if (!signerValue) throw new CeremonyHaltError('Connected wallet has no signer account.')
    const signer = getAddress(signerValue)
    if (!owners.some((owner) => owner.toLowerCase() === signer.toLowerCase())) {
      throw new CeremonyHaltError(`${signer} is not an owner of Safe ${safe}.`)
    }
    return { safe, signer, threshold }
  }

  private async safeTransaction(manifest: BundleManifest) {
    return this.protocolKit.createTransaction({
      transactions: [
        {
          to: manifest.safeTransaction.to,
          value: manifest.safeTransaction.value,
          data: manifest.safeTransaction.data,
          operation: OperationType.DelegateCall,
        },
      ],
    })
  }

  async resume(): Promise<number> {
    await this.assertContext()
    const state = this.store.load()
    assertRunStateIds(this.plan, state)
    let foundIncomplete = false

    for (const [index, manifest] of this.manifests.entries()) {
      const entries = manifest.innerTransactions.map((entry) => state[entry.planId])
      const allVerified = entries.every((entry) => entry?.status === 'verified')
      const anyVerified = entries.some((entry) => entry?.status === 'verified')
      const hashes = new Set(entries.map((entry) => entry?.txHash).filter(Boolean))
      if (allVerified) {
        if (foundIncomplete) {
          throw new CeremonyHaltError(`Run state is non-contiguous at bundle ${manifest.bundle.number}.`)
        }
        await this.verifyPredicates(manifest)
        continue
      }
      foundIncomplete = true
      if (anyVerified || hashes.size > 1) {
        throw new CeremonyHaltError(`Bundle ${manifest.bundle.number} has a partial or inconsistent run state.`)
      }
      const txHash = entries.find((entry) => entry?.txHash)?.txHash
      if (!txHash) return index
      const receipt = await this.transport.getReceipt(txHash)
      if (!receipt || receipt.status !== 'success') {
        throw new CeremonyHaltError(
          `Resume halted: bundle ${manifest.bundle.number} is not successfully mined.`,
        )
      }
      await this.verifyAndRecord(manifest, receipt)
    }
    return this.manifests.length
  }

  async getProgress(bundleIndex: number): Promise<SignatureProgress | null> {
    if (!this.apiKit) return null
    const transaction = await this.safeTransaction(this.manifests[bundleIndex])
    const safeTxHash = asHex(await this.protocolKit.getTransactionHash(transaction))
    try {
      const serviceTransaction = await this.apiKit.getTransaction(safeTxHash)
      return this.progressFromService(serviceTransaction)
    } catch {
      return {
        safeTxHash,
        confirmations: 0,
        threshold: await this.protocolKit.getThreshold(),
        executed: false,
        executionTxHash: null,
      }
    }
  }

  async getProgressByHash(safeTxHash: Hex): Promise<SignatureProgress | null> {
    if (!this.apiKit) return null
    return this.progressFromService(await this.apiKit.getTransaction(safeTxHash))
  }

  async syncExecuted(bundleIndex: number, safeTxHash: Hex): Promise<SafeBundleResult | null> {
    if (!this.apiKit) return null
    const serviceTransaction = await this.apiKit.getTransaction(safeTxHash)
    const progress = this.progressFromService(serviceTransaction)
    if (!progress.executed || !progress.executionTxHash) return null
    const receipt = await this.transport.getReceipt(progress.executionTxHash)
    if (!receipt || receipt.status !== 'success') {
      throw new CeremonyHaltError(
        `Safe service reports execution ${progress.executionTxHash}, but its successful receipt is unavailable.`,
      )
    }
    const predicateDetails = await this.verifyAndRecord(this.manifests[bundleIndex], receipt)
    return {
      safeTxHash,
      executionTxHash: progress.executionTxHash,
      progress,
      runState: this.store.load(),
      predicateDetails,
      direct: false,
    }
  }

  async propose(bundleIndex: number): Promise<SafeBundleResult> {
    const context = await this.assertContext()
    const manifest = this.manifests[bundleIndex]
    if (!manifest) throw new Error(`Unknown bundle index ${bundleIndex}.`)
    const transaction = await this.safeTransaction(manifest)
    const safeTxHash = asHex(await this.protocolKit.getTransactionHash(transaction))

    if (this.apiKit) {
      const signature = await this.protocolKit.signHash(safeTxHash)
      try {
        await this.apiKit.proposeTransaction({
          safeAddress: context.safe,
          safeTransactionData: transaction.data,
          safeTxHash,
          senderAddress: context.signer,
          senderSignature: signature.data,
          origin: `Wildcat ${this.plan.release} deployment ceremony`,
        })
      } catch (error) {
        if (context.threshold !== 1) {
          throw new CeremonyHaltError(
            `Safe Transaction Service proposal failed and direct execution is unsafe at threshold ${context.threshold}: ${(error as Error).message}`,
          )
        }
        return this.executeDirect(manifest, transaction, safeTxHash)
      }
      const progress = await this.getProgressByHash(safeTxHash)
      if (!progress) throw new Error('Safe service did not return proposal progress.')
      return {
        safeTxHash,
        progress,
        runState: this.store.load(),
        predicateDetails: [],
        direct: false,
      }
    }

    if (context.threshold !== 1) {
      throw new CeremonyHaltError(
        `Safe Transaction Service is unavailable and direct airgapped execution requires threshold 1; this Safe threshold is ${context.threshold}.`,
      )
    }
    return this.executeDirect(manifest, transaction, safeTxHash)
  }

  private async executeDirect(
    manifest: BundleManifest,
    transaction: SafeTransaction,
    safeTxHash: Hex,
  ): Promise<SafeBundleResult> {
    const signed = await this.protocolKit.signTransaction(transaction)
    const result = await this.protocolKit.executeTransaction(signed)
    const executionTxHash = asHex(result.hash)
    const receipt = await this.transport.waitForReceipt(executionTxHash)
    if (receipt.status !== 'success') {
      throw new CeremonyHaltError(`Safe execution reverted: ${executionTxHash}`)
    }
    const predicateDetails = await this.verifyAndRecord(manifest, receipt)
    return {
      safeTxHash,
      executionTxHash,
      progress: {
        safeTxHash,
        confirmations: 1,
        threshold: 1,
        executed: true,
        executionTxHash,
      },
      runState: this.store.load(),
      predicateDetails,
      direct: true,
    }
  }

  async sign(bundleIndex: number): Promise<SignatureProgress> {
    if (!this.apiKit) throw new CeremonyHaltError('No Safe Transaction Service is configured.')
    const context = await this.assertContext()
    const transaction = await this.safeTransaction(this.manifests[bundleIndex])
    const safeTxHash = asHex(await this.protocolKit.getTransactionHash(transaction))
    const serviceTransaction = await this.apiKit.getTransaction(safeTxHash)
    if (serviceTransaction.confirmations?.some(
      (confirmation) => confirmation.owner.toLowerCase() === context.signer.toLowerCase(),
    )) {
      return this.progressFromService(serviceTransaction)
    }
    const signature = await this.protocolKit.signHash(safeTxHash)
    await this.apiKit.confirmTransaction(safeTxHash, signature.data)
    return this.progressFromService(await this.apiKit.getTransaction(safeTxHash))
  }

  async execute(bundleIndex: number): Promise<SafeBundleResult> {
    if (!this.apiKit) return this.propose(bundleIndex)
    await this.assertContext()
    const transaction = await this.safeTransaction(this.manifests[bundleIndex])
    const safeTxHash = asHex(await this.protocolKit.getTransactionHash(transaction))
    const serviceTransaction = await this.apiKit.getTransaction(safeTxHash)
    const progress = this.progressFromService(serviceTransaction)
    if (progress.confirmations < progress.threshold) {
      throw new CeremonyHaltError(
        `Safe transaction has ${progress.confirmations} of ${progress.threshold} required signatures.`,
      )
    }
    const result = await this.protocolKit.executeTransaction(serviceTransaction)
    const executionTxHash = asHex(result.hash)
    const receipt = await this.transport.waitForReceipt(executionTxHash)
    if (receipt.status !== 'success') {
      throw new CeremonyHaltError(`Safe execution reverted: ${executionTxHash}`)
    }
    const predicateDetails = await this.verifyAndRecord(
      this.manifests[bundleIndex],
      receipt,
    )
    return {
      safeTxHash,
      executionTxHash,
      progress: {
        ...progress,
        executed: true,
        executionTxHash,
      },
      runState: this.store.load(),
      predicateDetails,
      direct: false,
    }
  }

  private progressFromService(
    transaction: SafeMultisigTransactionResponse,
  ): SignatureProgress {
    return {
      safeTxHash: asHex(transaction.safeTxHash),
      confirmations: transaction.confirmations?.length ?? 0,
      threshold: transaction.confirmationsRequired,
      executed: transaction.isExecuted,
      executionTxHash: transaction.transactionHash
        ? asHex(transaction.transactionHash)
        : null,
    }
  }

  private async verifyPredicates(manifest: BundleManifest): Promise<string[]> {
    const details: string[] = []
    for (const entry of manifest.innerTransactions) {
      const predicate = await evaluatePredicate(
        this.transport,
        entry.predicate,
        new Map<string, Address>(),
      )
      if (!predicate.ok) {
        throw new CeremonyHaltError(
          `Predicate failed for ${entry.planId}: ${predicate.detail}`,
          entry.planId,
        )
      }
      details.push(`${entry.planId}: ${predicate.detail}`)
    }
    return details
  }

  private async verifyAndRecord(
    manifest: BundleManifest,
    receipt: ReceiptLike,
  ): Promise<string[]> {
    const state = this.store.load()
    for (const entry of manifest.innerTransactions) {
      state[entry.planId] = {
        txHash: receipt.transactionHash,
        blockNumber: receiptBlockNumber(receipt.blockNumber),
        status: 'mined',
        ...(entry.kind === 'deploy' && entry.precomputedAddress
          ? { resolvedAddress: getAddress(entry.precomputedAddress) }
          : {}),
      }
    }
    this.store.save(state)

    const details: string[] = []
    for (const entry of manifest.innerTransactions) {
      let predicate
      try {
        predicate = await evaluatePredicate(
          this.transport,
          entry.predicate,
          new Map<string, Address>(),
        )
      } catch (error) {
        state[entry.planId].status = 'predicate-failed'
        this.store.save(state)
        throw new CeremonyHaltError(
          `Predicate error for ${entry.planId}: ${(error as Error).message}`,
          entry.planId,
        )
      }
      if (!predicate.ok) {
        state[entry.planId].status = 'predicate-failed'
        this.store.save(state)
        throw new CeremonyHaltError(
          `Predicate failed for ${entry.planId}: ${predicate.detail}`,
          entry.planId,
        )
      }
      details.push(`${entry.planId}: ${predicate.detail}`)
    }
    for (const entry of manifest.innerTransactions) state[entry.planId].status = 'verified'
    this.store.save(state)
    return details
  }
}

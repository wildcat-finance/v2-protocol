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
  compileSafePlan,
  compileSafeTransactionData,
  type CompiledSafePlan,
  type CompiledSafeTransactionData,
} from './safeCompiler'
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
  | 'getContractVersion'
  | 'getNonce'
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

function isNotFound(error: unknown): boolean {
  return typeof error === 'object' && error !== null &&
    'statusCode' in error && (error as { statusCode?: unknown }).statusCode === 404
}

function sortManifests(manifests: BundleManifest[]): BundleManifest[] {
  return [...manifests].sort((left, right) => left.bundle.number - right.bundle.number)
}

function canonicalArtifactValue(value: unknown): unknown {
  if (typeof value === 'bigint' || typeof value === 'number') return value.toString()
  if (typeof value === 'string' && /^0x[a-fA-F0-9]*$/.test(value)) {
    return value.toLowerCase()
  }
  if (Array.isArray(value)) return value.map(canonicalArtifactValue)
  if (value !== null && typeof value === 'object') {
    return Object.fromEntries(
      Object.keys(value)
        .sort()
        .map((key) => [
          key,
          canonicalArtifactValue((value as Record<string, unknown>)[key]),
        ]),
    )
  }
  return value
}

function sameCanonicalValue(left: unknown, right: unknown): boolean {
  return JSON.stringify(canonicalArtifactValue(left)) ===
    JSON.stringify(canonicalArtifactValue(right))
}

function assertPositiveGas(value: string, context: string): bigint {
  if (!/^[1-9][0-9]*$/.test(value)) throw new Error(`${context} must be a positive decimal gas value.`)
  return BigInt(value)
}

function safeNonce(value: string, context: string): bigint {
  if (!/^(?:0|[1-9][0-9]*)$/.test(value)) {
    throw new Error(`${context} must be a non-negative decimal Safe nonce.`)
  }
  const nonce = BigInt(value)
  if (nonce > BigInt(Number.MAX_SAFE_INTEGER)) {
    throw new Error(`${context} exceeds the supported Safe nonce range.`)
  }
  return nonce
}

export function validateBundleArtifacts(
  plan: DeploymentPlan,
  planHash: Hex,
  manifests: BundleManifest[],
  expectedAddresses: ExpectedAddresses,
): BundleManifest[] {
  if (manifests.length === 0) throw new Error('At least one bundle manifest is required.')
  const ordered = sortManifests(manifests)
  const compiled = compileSafePlan(plan)
  const seenPlanIds: string[] = []
  const safe = ordered[0].safe.address.toLowerCase()
  const startNonce = safeNonce(ordered[0].bundle.safeNonce, 'Bundle 1 safeNonce')

  if (!sameCanonicalValue(expectedAddresses, compiled.expectedAddresses)) {
    throw new Error('expected-addresses.json does not match addresses compiled from the plan.')
  }

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
    const nonce = safeNonce(
      manifest.bundle.safeNonce,
      `Bundle ${manifest.bundle.number} safeNonce`,
    )
    if (nonce !== startNonce + BigInt(index)) {
      throw new Error('Bundle Safe nonces must be contiguous in bundle order.')
    }
    const maxGas = assertPositiveGas(manifest.bundle.maxGas, `Bundle ${manifest.bundle.number} maxGas`)
    assertPositiveGas(
      manifest.bundle.staticGasEstimate,
      `Bundle ${manifest.bundle.number} staticGasEstimate`,
    )
    if (manifest.bundle.simulatedGas !== null) {
      const simulatedGas = assertPositiveGas(
        manifest.bundle.simulatedGas,
        `Bundle ${manifest.bundle.number} simulatedGas`,
      )
      if (simulatedGas > maxGas) {
        throw new Error(`Bundle ${manifest.bundle.number} simulated gas exceeds its ceiling.`)
      }
    } else if (plan.chainId === 1) {
      throw new Error(
        `Bundle ${manifest.bundle.number} must include successful fork-simulated gas before mainnet use.`,
      )
    }

    const compiledEntries = []
    for (const entry of manifest.innerTransactions) {
      const expected = compiled.entries[entry.planIndex]
      if (!expected || expected.planId !== entry.planId) {
        throw new Error(`Bundle ${manifest.bundle.number} contains an invalid plan index/id pair.`)
      }
      const fields = [
        'kind',
        'description',
        'operation',
        'to',
        'logicalTarget',
        'value',
        'data',
        'decodedArgs',
        'predicate',
        'precomputedAddress',
        'salt',
        'initCodeHash',
      ] as const
      for (const field of fields) {
        if (!sameCanonicalValue(entry[field], expected[field])) {
          throw new Error(
            `Bundle ${manifest.bundle.number} ${entry.planId}.${field} does not match the plan compiler.`,
          )
        }
      }
      assertPositiveGas(entry.staticGasEstimate, `${entry.planId}.staticGasEstimate`)
      if (entry.simulatedGas !== null) {
        assertPositiveGas(entry.simulatedGas, `${entry.planId}.simulatedGas`)
      } else if (plan.chainId === 1) {
        throw new Error(`${entry.planId} must include fork-simulated gas before mainnet use.`)
      }
      compiledEntries.push(expected)
      seenPlanIds.push(entry.planId)
    }
    const expectedSafeTransaction = compileSafeTransactionData(
      plan.chainId,
      getAddress(manifest.safe.address),
      nonce,
      compiledEntries,
    )
    if (!sameCanonicalValue(manifest.safeTransaction, expectedSafeTransaction)) {
      throw new Error(
        `Bundle ${manifest.bundle.number} Safe transaction does not match the plan compiler.`,
      )
    }
  })

  const planIds = plan.transactions.map((transaction) => transaction.id)
  if (JSON.stringify(seenPlanIds) !== JSON.stringify(planIds)) {
    throw new Error('Bundles must cover every plan entry exactly once and in plan order.')
  }
  return ordered
}

export class SafeCeremony {
  readonly manifests: BundleManifest[]
  private readonly compiledPlan: CompiledSafePlan

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
    this.compiledPlan = compileSafePlan(plan)
    this.manifests = validateBundleArtifacts(plan, planHash, manifests, expectedAddresses)
  }

  getRunState(): RunState {
    return this.store.load()
  }

  private expectedNonce(bundleIndex: number): number {
    const manifest = this.manifests[bundleIndex]
    if (!manifest) throw new CeremonyHaltError(`Unknown bundle index ${bundleIndex}.`)
    return Number(safeNonce(manifest.bundle.safeNonce, `Bundle ${manifest.bundle.number} safeNonce`))
  }

  private async assertCurrentNonce(bundleIndex: number): Promise<void> {
    const expected = this.expectedNonce(bundleIndex)
    const actual = await this.protocolKit.getNonce()
    if (actual !== expected) {
      throw new CeremonyHaltError(
        `Safe nonce mismatch at bundle ${bundleIndex + 1}: package requires ${expected}, Safe is at ${actual}. Do not sign or resend; reconcile the known Safe transaction hash first.`,
      )
    }
  }

  private async assertContext(): Promise<{
    safe: Address
    signer: Address
    threshold: number
  }> {
    const [chainId, safeValue, safeVersion, owners, signerValue, threshold] = await Promise.all([
      this.transport.getChainId(),
      this.protocolKit.getAddress(),
      this.protocolKit.getContractVersion(),
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
    if (safeVersion !== '1.4.1') {
      throw new CeremonyHaltError(
        `Safe version mismatch: ceremony requires 1.4.1, loaded Safe is ${safeVersion}.`,
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
    const compiled = this.compiledSafeTransaction(manifest)
    const transaction = await this.protocolKit.createTransaction({
      transactions: [
        {
          to: compiled.to,
          value: compiled.value,
          data: compiled.data,
          operation: OperationType.DelegateCall,
        },
      ],
      options: {
        safeTxGas: compiled.safeTxGas,
        baseGas: compiled.baseGas,
        gasPrice: compiled.gasPrice,
        gasToken: compiled.gasToken,
        refundReceiver: compiled.refundReceiver,
        nonce: Number(compiled.nonce),
      },
    })
    const actualHash = asHex(await this.protocolKit.getTransactionHash(transaction))
    if (actualHash.toLowerCase() !== compiled.safeTxHash.toLowerCase()) {
      throw new CeremonyHaltError(
        `Bundle ${manifest.bundle.number} Safe hash mismatch: package=${compiled.safeTxHash}, Safe SDK=${actualHash}.`,
      )
    }
    return transaction
  }

  private compiledSafeTransaction(
    manifest: BundleManifest | undefined,
  ): CompiledSafeTransactionData {
    if (!manifest) throw new CeremonyHaltError('Unknown Safe bundle index.')
    const entries = manifest.innerTransactions.map((entry) => {
      const compiled = this.compiledPlan.entries[entry.planIndex]
      if (!compiled || compiled.planId !== entry.planId) {
        throw new CeremonyHaltError(`Bundle ${manifest.bundle.number} no longer matches the plan.`)
      }
      return compiled
    })
    return compileSafeTransactionData(
      this.plan.chainId,
      getAddress(manifest.safe.address),
      safeNonce(manifest.bundle.safeNonce, `Bundle ${manifest.bundle.number} safeNonce`),
      entries,
    )
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
      if (!txHash) {
        const progress = await this.getProgress(index)
        if (progress?.executed && progress.executionTxHash) {
          await this.syncExecuted(index, progress.safeTxHash)
          continue
        }
        await this.assertCurrentNonce(index)
        return index
      }
      const receipt = await this.transport.getReceipt(txHash)
      if (!receipt) {
        throw new CeremonyHaltError(
          `Resume halted: bundle ${manifest.bundle.number} was submitted as ${txHash} but has no receipt yet; do not resend it.`,
        )
      }
      if (receipt.status !== 'success') {
        this.recordReceiptStatus(manifest, receipt)
        throw new CeremonyHaltError(
          `Resume halted: bundle ${manifest.bundle.number} execution reverted as ${txHash}.`,
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
      return await this.progressFromService(bundleIndex, serviceTransaction)
    } catch (error) {
      if (!isNotFound(error)) {
        throw new CeremonyHaltError(
          `Safe Transaction Service lookup failed for ${safeTxHash}: ${(error as Error).message}`,
        )
      }
      return {
        safeTxHash,
        confirmations: 0,
        threshold: await this.protocolKit.getThreshold(),
        executed: false,
        executionTxHash: null,
      }
    }
  }

  async getProgressByHash(
    bundleIndex: number,
    safeTxHash: Hex,
  ): Promise<SignatureProgress | null> {
    if (!this.apiKit) return null
    const expectedHash = this.compiledSafeTransaction(this.manifests[bundleIndex]).safeTxHash
    if (safeTxHash.toLowerCase() !== expectedHash.toLowerCase()) {
      throw new CeremonyHaltError(
        `Bundle ${bundleIndex + 1} progress hash ${safeTxHash} does not match package hash ${expectedHash}.`,
      )
    }
    return await this.progressFromService(
      bundleIndex,
      await this.apiKit.getTransaction(safeTxHash),
    )
  }

  async syncExecuted(bundleIndex: number, safeTxHash: Hex): Promise<SafeBundleResult | null> {
    if (!this.apiKit) return null
    const serviceTransaction = await this.apiKit.getTransaction(safeTxHash)
    const progress = await this.progressFromService(bundleIndex, serviceTransaction)
    if (!progress.executed || !progress.executionTxHash) return null
    this.recordSubmitted(this.manifests[bundleIndex], progress.executionTxHash)
    let receipt = await this.transport.getReceipt(progress.executionTxHash)
    if (!receipt) {
      try {
        receipt = await this.transport.waitForReceipt(progress.executionTxHash)
      } catch (error) {
        throw new CeremonyHaltError(
          `Safe service reports execution ${progress.executionTxHash}, but receipt waiting failed: ${(error as Error).message}. Resume instead of resending.`,
        )
      }
    }
    if (receipt.status !== 'success') {
      this.recordReceiptStatus(this.manifests[bundleIndex], receipt)
      throw new CeremonyHaltError(
        `Safe service reports execution ${progress.executionTxHash}, but the transaction reverted.`,
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
    await this.assertCurrentNonce(bundleIndex)
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
      const progress = await this.getProgressByHash(bundleIndex, safeTxHash)
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
    this.recordSubmitted(manifest, executionTxHash)
    let receipt
    try {
      receipt = await this.transport.waitForReceipt(executionTxHash)
    } catch (error) {
      throw new CeremonyHaltError(
        `Bundle ${manifest.bundle.number} was submitted as ${executionTxHash}, but receipt waiting failed: ${(error as Error).message}. Resume instead of resending.`,
      )
    }
    if (receipt.status !== 'success') {
      this.recordReceiptStatus(manifest, receipt)
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
    await this.assertCurrentNonce(bundleIndex)
    const transaction = await this.safeTransaction(this.manifests[bundleIndex])
    const safeTxHash = asHex(await this.protocolKit.getTransactionHash(transaction))
    const serviceTransaction = await this.apiKit.getTransaction(safeTxHash)
    const currentProgress = await this.progressFromService(bundleIndex, serviceTransaction)
    if (serviceTransaction.confirmations?.some(
      (confirmation) => confirmation.owner.toLowerCase() === context.signer.toLowerCase(),
    )) {
      return currentProgress
    }
    const signature = await this.protocolKit.signHash(safeTxHash)
    await this.apiKit.confirmTransaction(safeTxHash, signature.data)
    return await this.progressFromService(
      bundleIndex,
      await this.apiKit.getTransaction(safeTxHash),
    )
  }

  async execute(bundleIndex: number): Promise<SafeBundleResult> {
    if (!this.apiKit) return this.propose(bundleIndex)
    await this.assertContext()
    await this.assertCurrentNonce(bundleIndex)
    const transaction = await this.safeTransaction(this.manifests[bundleIndex])
    const safeTxHash = asHex(await this.protocolKit.getTransactionHash(transaction))
    const serviceTransaction = await this.apiKit.getTransaction(safeTxHash)
    const progress = await this.progressFromService(bundleIndex, serviceTransaction)
    if (progress.confirmations < progress.threshold) {
      throw new CeremonyHaltError(
        `Safe transaction has ${progress.confirmations} of ${progress.threshold} required signatures.`,
      )
    }
    const result = await this.protocolKit.executeTransaction(serviceTransaction)
    const executionTxHash = asHex(result.hash)
    const manifest = this.manifests[bundleIndex]
    this.recordSubmitted(manifest, executionTxHash)
    let receipt
    try {
      receipt = await this.transport.waitForReceipt(executionTxHash)
    } catch (error) {
      throw new CeremonyHaltError(
        `Bundle ${manifest.bundle.number} was submitted as ${executionTxHash}, but receipt waiting failed: ${(error as Error).message}. Resume instead of resending.`,
      )
    }
    if (receipt.status !== 'success') {
      this.recordReceiptStatus(manifest, receipt)
      throw new CeremonyHaltError(`Safe execution reverted: ${executionTxHash}`)
    }
    const predicateDetails = await this.verifyAndRecord(
      manifest,
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

  private async progressFromService(
    bundleIndex: number,
    transaction: SafeMultisigTransactionResponse,
  ): Promise<SignatureProgress> {
    const manifest = this.manifests[bundleIndex]
    if (!manifest) throw new CeremonyHaltError(`Unknown bundle index ${bundleIndex}.`)
    const expected = this.compiledSafeTransaction(manifest)
    let actual
    let serviceSafe
    try {
      serviceSafe = getAddress(transaction.safe)
      actual = {
        to: getAddress(transaction.to),
        value: BigInt(transaction.value).toString(),
        data: asHex(transaction.data ?? '0x'),
        operation: transaction.operation,
        safeTxGas: BigInt(transaction.safeTxGas).toString(),
        baseGas: BigInt(transaction.baseGas).toString(),
        gasPrice: BigInt(transaction.gasPrice).toString(),
        gasToken: getAddress(transaction.gasToken),
        refundReceiver: getAddress(transaction.refundReceiver ?? expected.refundReceiver),
        nonce: BigInt(transaction.nonce).toString(),
        safeTxHash: asHex(transaction.safeTxHash),
      }
    } catch (error) {
      throw new CeremonyHaltError(
        `Safe Transaction Service returned malformed transaction data for bundle ${manifest.bundle.number}: ${(error as Error).message}`,
      )
    }
    if (serviceSafe.toLowerCase() !== this.plan.expectedExecutor.toLowerCase()) {
      throw new CeremonyHaltError(
        `Safe Transaction Service returned transaction data for unexpected Safe ${serviceSafe}.`,
      )
    }
    if (!sameCanonicalValue(actual, expected)) {
      throw new CeremonyHaltError(
        `Safe Transaction Service transaction does not match compiled bundle ${manifest.bundle.number}.`,
      )
    }
    if (transaction.isExecuted && !transaction.transactionHash) {
      throw new CeremonyHaltError(
        `Safe Transaction Service reports bundle ${manifest.bundle.number} executed without an execution transaction hash.`,
      )
    }
    const [threshold, owners] = await Promise.all([
      this.protocolKit.getThreshold(),
      this.protocolKit.getOwners(),
    ])
    if (transaction.confirmationsRequired !== threshold) {
      throw new CeremonyHaltError(
        `Safe Transaction Service threshold ${transaction.confirmationsRequired} does not match on-chain threshold ${threshold}.`,
      )
    }
    const ownerSet = new Set(owners.map((owner) => owner.toLowerCase()))
    const confirmingOwners = new Set(
      (transaction.confirmations ?? []).map((confirmation) => confirmation.owner.toLowerCase()),
    )
    const invalidOwner = [...confirmingOwners].find((owner) => !ownerSet.has(owner))
    if (invalidOwner) {
      throw new CeremonyHaltError(
        `Safe Transaction Service reports a confirmation from non-owner ${invalidOwner}.`,
      )
    }
    return {
      safeTxHash: asHex(transaction.safeTxHash),
      confirmations: confirmingOwners.size,
      threshold,
      executed: transaction.isExecuted,
      executionTxHash: transaction.transactionHash
        ? asHex(transaction.transactionHash)
        : null,
    }
  }

  private recordSubmitted(manifest: BundleManifest, txHash: Hex): void {
    const state = this.store.load()
    for (const entry of manifest.innerTransactions) {
      const existing = state[entry.planId]
      if (existing?.status === 'verified') {
        if (existing.txHash.toLowerCase() === txHash.toLowerCase()) continue
        throw new CeremonyHaltError(`${entry.planId} is already verified; refusing to overwrite it.`)
      }
      if (existing?.txHash && existing.txHash.toLowerCase() !== txHash.toLowerCase()) {
        throw new CeremonyHaltError(
          `${entry.planId} already records submitted transaction ${existing.txHash}; refusing to replace it with ${txHash}.`,
        )
      }
      state[entry.planId] = {
        txHash,
        status: 'submitted',
        ...(entry.kind === 'deploy' && entry.precomputedAddress
          ? { resolvedAddress: getAddress(entry.precomputedAddress) }
          : {}),
      }
    }
    this.store.save(state)
  }

  private recordReceiptStatus(manifest: BundleManifest, receipt: ReceiptLike): void {
    const state = this.store.load()
    for (const entry of manifest.innerTransactions) {
      state[entry.planId] = {
        ...state[entry.planId],
        txHash: receipt.transactionHash,
        blockNumber: receiptBlockNumber(receipt.blockNumber),
        status: receipt.status === 'success' ? 'mined' : 'reverted',
        ...(entry.kind === 'deploy' && entry.precomputedAddress
          ? { resolvedAddress: getAddress(entry.precomputedAddress) }
          : {}),
      }
    }
    this.store.save(state)
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

import {
  getAddress,
  type Address,
  type Hex,
} from 'viem'
import { evaluatePredicate } from './predicates'
import { buildPlanPayload } from './planEncoding'
import {
  assertRunStateIds,
  outputsFromRunState,
  receiptBlockNumber,
  stateEntryFromReceipt,
  type ProgressStore,
  type RunState,
} from './runState'
import type {
  DeploymentPlan,
  ExecutionTransport,
  PlanTransaction,
} from './types'

export class CeremonyHaltError extends Error {
  constructor(message: string, readonly transactionId?: string) {
    super(message)
    this.name = 'CeremonyHaltError'
  }
}

export interface PreparedTransaction {
  index: number
  transaction: PlanTransaction
  account: Address
  nonce: number
  to?: Address
  data: Hex
  value: bigint
  estimatedGas: bigint
  gasLimit: bigint
}

export interface ExecutionResult {
  transaction: PlanTransaction
  predicateDetail: string
  runState: RunState
}

export class PlanExecutor {
  constructor(
    readonly plan: DeploymentPlan,
    private readonly transport: ExecutionTransport,
    private readonly store: ProgressStore,
  ) {}

  getRunState(): RunState {
    return this.store.load()
  }

  private async assertContext(): Promise<Address> {
    const [chainId, account] = await Promise.all([
      this.transport.getChainId(),
      this.transport.getAccount(),
    ])
    if (chainId !== this.plan.chainId) {
      throw new CeremonyHaltError(
        `Chain mismatch: plan requires ${this.plan.chainId}, wallet is on ${chainId}.`,
      )
    }
    if (account.toLowerCase() !== this.plan.expectedExecutor.toLowerCase()) {
      throw new CeremonyHaltError(
        `Executor mismatch: plan requires ${this.plan.expectedExecutor}, connected ${account}.`,
      )
    }
    return getAddress(account)
  }

  private async recoverCompensatingTransactions(
    state: RunState,
    outputs: Map<string, Address>,
  ): Promise<void> {
    const transactions = new Map(
      this.plan.transactions.map((transaction) => [transaction.id, transaction]),
    )
    for (const transaction of this.plan.transactions) {
      if (!transaction.reverifyUntil) continue
      const compensation = transactions.get(transaction.reverifyUntil)
      if (!compensation) continue
      const existing = state[compensation.id]
      if (!existing?.txHash || existing.status === 'verified') continue

      const receipt = await this.transport.getReceipt(existing.txHash)
      if (!receipt) {
        throw new CeremonyHaltError(
          `Resume halted: compensating transaction ${compensation.id} has no receipt yet; do not resend it.`,
          compensation.id,
        )
      }
      existing.blockNumber = receiptBlockNumber(receipt.blockNumber)
      existing.status = receipt.status === 'success' ? 'mined' : 'reverted'
      if (receipt.status !== 'success') {
        this.store.save(state)
        throw new CeremonyHaltError(
          `Resume halted: compensating transaction ${compensation.id} reverted.`,
          compensation.id,
        )
      }
      if (compensation.kind === 'deploy') {
        if (!receipt.contractAddress) {
          existing.status = 'predicate-failed'
          this.store.save(state)
          throw new CeremonyHaltError(
            `Deployment receipt lacks contractAddress: ${compensation.id}`,
            compensation.id,
          )
        }
        const resolvedAddress = getAddress(receipt.contractAddress)
        if (
          existing.resolvedAddress &&
          existing.resolvedAddress.toLowerCase() !== resolvedAddress.toLowerCase()
        ) {
          throw new CeremonyHaltError(
            `Stored deployment address for ${compensation.id} does not match its receipt.`,
            compensation.id,
          )
        }
        existing.resolvedAddress = resolvedAddress
        outputs.set(compensation.output, resolvedAddress)
      }
      this.store.save(state)
      const predicate = await evaluatePredicate(
        this.transport,
        compensation.predicate,
        outputs,
      )
      if (!predicate.ok) {
        existing.status = 'predicate-failed'
        this.store.save(state)
        throw new CeremonyHaltError(
          `Resume halted: compensating transaction ${compensation.id} fails its predicate: ${predicate.detail}`,
          compensation.id,
        )
      }
      existing.status = 'verified'
      this.store.save(state)
    }
  }

  async resume(): Promise<number> {
    await this.assertContext()
    const state = this.store.load()
    assertRunStateIds(this.plan, state)
    const outputs = outputsFromRunState(this.plan, state)
    await this.recoverCompensatingTransactions(state, outputs)
    let sawIncomplete = false
    for (const transaction of this.plan.transactions) {
      const verified = state[transaction.id]?.status === 'verified'
      if (!verified) sawIncomplete = true
      if (verified && sawIncomplete) {
        throw new CeremonyHaltError(
          `Run state is non-contiguous: ${transaction.id} is verified after an incomplete entry.`,
          transaction.id,
        )
      }
    }
    let foundIncomplete = false

    for (const [index, transaction] of this.plan.transactions.entries()) {
      const existing = state[transaction.id]
      if (existing?.status === 'verified') {
        if (foundIncomplete) {
          throw new CeremonyHaltError(
            `Run state is non-contiguous: ${transaction.id} is verified after an incomplete entry.`,
            transaction.id,
          )
        }
        if (
          transaction.reverifyUntil &&
          state[transaction.reverifyUntil]?.status === 'verified'
        ) {
          continue
        }
        const predicate = await evaluatePredicate(this.transport, transaction.predicate, outputs)
        if (!predicate.ok) {
          throw new CeremonyHaltError(
            `Resume halted: prior predicate failed for ${transaction.id}: ${predicate.detail}`,
            transaction.id,
          )
        }
        continue
      }

      foundIncomplete = true
      if (!existing?.txHash) return index
      const receipt = await this.transport.getReceipt(existing.txHash)
      if (!receipt) {
        throw new CeremonyHaltError(
          `Resume halted: submitted transaction ${transaction.id} has no receipt yet; do not resend it.`,
          transaction.id,
        )
      }
      existing.blockNumber = receiptBlockNumber(receipt.blockNumber)
      existing.status = receipt.status === 'success' ? 'mined' : 'reverted'
      if (receipt.status !== 'success') {
        this.store.save(state)
        throw new CeremonyHaltError(
          `Resume halted: stored transaction ${transaction.id} reverted.`,
          transaction.id,
        )
      }
      if (transaction.kind === 'deploy') {
        if (!receipt.contractAddress) {
          throw new CeremonyHaltError(
            `Deployment receipt lacks contractAddress: ${transaction.id}`,
            transaction.id,
          )
        }
        const resolvedAddress = getAddress(receipt.contractAddress)
        if (
          existing.resolvedAddress &&
          existing.resolvedAddress.toLowerCase() !== resolvedAddress.toLowerCase()
        ) {
          throw new CeremonyHaltError(
            `Stored deployment address for ${transaction.id} does not match its receipt.`,
            transaction.id,
          )
        }
        existing.resolvedAddress = resolvedAddress
        outputs.set(transaction.output, existing.resolvedAddress)
      }
      this.store.save(state)
      const predicate = await evaluatePredicate(this.transport, transaction.predicate, outputs)
      if (!predicate.ok) {
        throw new CeremonyHaltError(
          `Resume halted: mined transaction ${transaction.id} still fails its predicate: ${predicate.detail}`,
          transaction.id,
        )
      }
      existing.status = 'verified'
      this.store.save(state)
    }
    return this.plan.transactions.length
  }

  private payload(transaction: PlanTransaction, outputs: ReadonlyMap<string, Address>) {
    try {
      return buildPlanPayload(transaction, outputs)
    } catch (error) {
      throw new CeremonyHaltError((error as Error).message, transaction.id)
    }
  }

  async prepareNext(): Promise<PreparedTransaction | null> {
    const index = await this.resume()
    if (index === this.plan.transactions.length) return null
    const account = await this.assertContext()
    const transaction = this.plan.transactions[index]
    const outputs = outputsFromRunState(this.plan, this.store.load())
    const payload = this.payload(transaction, outputs)
    const [nonce, estimate] = await Promise.all([
      this.transport.getTransactionCount(account),
      this.transport.estimateGas({ account, ...payload }),
    ])
    const policy = transaction.envelope.gasLimitPolicy
    const gasLimit =
      policy === 'estimate*1.3'
        ? (estimate * 13n + 9n) / 10n
        : BigInt(policy.gasLimit)
    return {
      index,
      transaction,
      account,
      nonce,
      ...payload,
      estimatedGas: estimate,
      gasLimit,
    }
  }

  async execute(prepared: PreparedTransaction): Promise<ExecutionResult> {
    const account = await this.assertContext()
    const state = this.store.load()
    if (state[prepared.transaction.id]?.txHash) {
      throw new CeremonyHaltError(
        `${prepared.transaction.id} already has a stored transaction hash; resume instead of resending.`,
        prepared.transaction.id,
      )
    }
    const currentNonce = await this.transport.getTransactionCount(account)
    if (currentNonce !== prepared.nonce) {
      throw new CeremonyHaltError(
        `Nonce changed: reviewed ${prepared.nonce}, wallet now reports ${currentNonce}. Review again.`,
        prepared.transaction.id,
      )
    }
    const txHash = await this.transport.sendTransaction({
      account,
      to: prepared.to,
      data: prepared.data,
      value: prepared.value,
      gas: prepared.gasLimit,
      nonce: prepared.nonce,
    })
    state[prepared.transaction.id] = { txHash, status: 'submitted' }
    this.store.save(state)

    let receipt
    try {
      receipt = await this.transport.waitForReceipt(txHash)
    } catch (error) {
      throw new CeremonyHaltError(
        `${prepared.transaction.id} was submitted as ${txHash}, but receipt waiting failed: ${(error as Error).message}. Resume instead of resending.`,
        prepared.transaction.id,
      )
    }
    const resolvedAddress =
      prepared.transaction.kind === 'deploy' && receipt.contractAddress
        ? getAddress(receipt.contractAddress)
        : undefined
    const entry = stateEntryFromReceipt(receipt, resolvedAddress)
    state[prepared.transaction.id] = entry
    this.store.save(state)

    if (receipt.status !== 'success') {
      throw new CeremonyHaltError(
        `Transaction reverted: ${prepared.transaction.id}`,
        prepared.transaction.id,
      )
    }
    if (prepared.transaction.kind === 'deploy' && !resolvedAddress) {
      entry.status = 'predicate-failed'
      this.store.save(state)
      throw new CeremonyHaltError(
        `Deployment receipt lacks contractAddress: ${prepared.transaction.id}`,
        prepared.transaction.id,
      )
    }

    const outputs = outputsFromRunState(this.plan, state)
    const predicate = await evaluatePredicate(
      this.transport,
      prepared.transaction.predicate,
      outputs,
    )
    if (!predicate.ok) {
      entry.status = 'predicate-failed'
      this.store.save(state)
      throw new CeremonyHaltError(
        `Predicate failed for ${prepared.transaction.id}: ${predicate.detail}`,
        prepared.transaction.id,
      )
    }
    entry.status = 'verified'
    this.store.save(state)
    return { transaction: prepared.transaction, predicateDetail: predicate.detail, runState: state }
  }
}

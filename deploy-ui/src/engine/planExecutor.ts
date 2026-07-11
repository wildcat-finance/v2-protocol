import {
  encodeAbiParameters,
  encodeFunctionData,
  getAddress,
  isAddress,
  parseAbiItem,
  parseAbiParameters,
  type AbiFunction,
  type Address,
  type Hex,
} from 'viem'
import { evaluatePredicate, isReference, resolveReferences } from './predicates'
import {
  assertRunStateIds,
  outputsFromRunState,
  stateEntryFromReceipt,
  type ProgressStore,
  type RunState,
} from './runState'
import type {
  DeploymentPlan,
  ExecutionTransport,
  PlanTransaction,
  PlanValue,
} from './types'

const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000' as Address

export class CeremonyHaltError extends Error {
  constructor(message: string, readonly transactionId?: string) {
    super(message)
    this.name = 'CeremonyHaltError'
  }
}

interface InferredValue {
  type: string
  value: unknown
}

function inferValue(value: PlanValue): InferredValue {
  if (isReference(value)) return { type: 'address', value: ZERO_ADDRESS }
  if (typeof value === 'boolean') return { type: 'bool', value }
  if (typeof value === 'number') {
    return value < 0
      ? { type: 'int256', value: BigInt(value) }
      : { type: 'uint256', value: BigInt(value) }
  }
  if (typeof value === 'string') {
    if (isAddress(value)) return { type: 'address', value: getAddress(value) }
    if (/^-?[0-9]+$/.test(value)) {
      return value.startsWith('-')
        ? { type: 'int256', value: BigInt(value) }
        : { type: 'uint256', value: BigInt(value) }
    }
    if (/^0x(?:[a-fA-F0-9]{2})*$/.test(value)) return { type: 'bytes', value }
    return { type: 'string', value }
  }
  if (value === null) throw new Error('Cannot infer an ABI type for null.')
  if (Array.isArray(value)) {
    if (value.length === 0) throw new Error('Cannot infer an ABI type for an empty array.')
    const entries = value.map(inferValue)
    if (!entries.every((entry) => entry.type === entries[0].type)) {
      throw new Error('Cannot infer one ABI type for a heterogeneous array.')
    }
    return { type: `${entries[0].type}[]`, value: entries.map((entry) => entry.value) }
  }
  const entries = Object.values(value).map(inferValue)
  return {
    type: `(${entries.map((entry) => entry.type).join(',')})`,
    value: entries.map((entry) => entry.value),
  }
}

function inferredEncoding(values: PlanValue[]): { types: string[]; encoded: Hex } {
  const inferred = values.map(inferValue)
  const parameters = parseAbiParameters(inferred.map((entry) => entry.type).join(','))
  return {
    types: inferred.map((entry) => entry.type),
    encoded: encodeAbiParameters(
      parameters,
      inferred.map((entry) => entry.value),
    ),
  }
}

function normalizeForAbi(value: PlanValue, parameter: { type: string; components?: readonly any[] }): unknown {
  if (parameter.type.endsWith(']')) {
    if (!Array.isArray(value)) throw new Error(`Expected array for ${parameter.type}.`)
    const itemType = parameter.type.replace(/\[[0-9]*\]$/, '')
    return value.map((entry) => normalizeForAbi(entry, { ...parameter, type: itemType }))
  }
  if (parameter.type === 'tuple') {
    if (value === null || typeof value !== 'object') throw new Error('Expected tuple value.')
    const values = Array.isArray(value) ? value : Object.values(value)
    return (parameter.components ?? []).map((component, index) =>
      normalizeForAbi(values[index] as PlanValue, component),
    )
  }
  if (/^u?int[0-9]*$/.test(parameter.type)) return BigInt(value as string | number)
  return value
}

function callAbi(signature: string): AbiFunction {
  const declaration = signature.trim().startsWith('function ')
    ? signature.trim()
    : `function ${signature.trim()}`
  const item = parseAbiItem(declaration)
  if (item.type !== 'function') throw new Error(`Invalid function signature: ${signature}`)
  return item
}

function replaceReferencesWithZero(value: PlanValue): PlanValue {
  if (isReference(value)) return ZERO_ADDRESS
  if (Array.isArray(value)) return value.map(replaceReferencesWithZero)
  if (value !== null && typeof value === 'object') {
    return Object.fromEntries(
      Object.entries(value).map(([key, entry]) => [key, replaceReferencesWithZero(entry)]),
    )
  }
  return value
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

  async resume(): Promise<number> {
    await this.assertContext()
    const state = this.store.load()
    assertRunStateIds(this.plan, state)
    const outputs = outputsFromRunState(this.plan, state)
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
      if (!receipt || receipt.status !== 'success') {
        throw new CeremonyHaltError(
          `Resume halted: stored transaction ${transaction.id} is not successfully mined.`,
          transaction.id,
        )
      }
      if (transaction.kind === 'deploy' && !existing.resolvedAddress) {
        if (!receipt.contractAddress) {
          throw new CeremonyHaltError(
            `Deployment receipt lacks contractAddress: ${transaction.id}`,
            transaction.id,
          )
        }
        existing.resolvedAddress = getAddress(receipt.contractAddress)
        outputs.set(transaction.output, existing.resolvedAddress)
      }
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
    const value = BigInt(transaction.envelope.value)
    if (transaction.kind === 'deploy') {
      const unresolved = inferredEncoding(transaction.constructorArgs.decoded)
      if (unresolved.encoded.toLowerCase() !== transaction.constructorArgs.encoded.toLowerCase()) {
        throw new CeremonyHaltError(
          `${transaction.id}: constructor ABI inference does not reproduce the reviewed encoded arguments.`,
          transaction.id,
        )
      }
      const resolved = resolveReferences(transaction.constructorArgs.decoded, outputs)
      const encoded = inferredEncoding(resolved).encoded
      return { data: `${transaction.initCode}${encoded.slice(2)}` as Hex, value }
    }

    const abi = callAbi(transaction.functionSignature)
    const unresolvedArgs = transaction.args.map((arg, index) =>
      normalizeForAbi(
        replaceReferencesWithZero(arg),
        abi.inputs[index] as { type: string; components?: readonly any[] },
      ),
    )
    const unresolvedData = encodeFunctionData({ abi: [abi], args: unresolvedArgs })
    if (unresolvedData.toLowerCase() !== transaction.calldata.toLowerCase()) {
      throw new CeremonyHaltError(
        `${transaction.id}: function signature and arguments do not reproduce the reviewed calldata.`,
        transaction.id,
      )
    }
    const resolvedArgs = resolveReferences(transaction.args, outputs).map((arg, index) =>
      normalizeForAbi(arg, abi.inputs[index] as { type: string; components?: readonly any[] }),
    )
    const toValue = resolveReferences(transaction.to, outputs)
    if (typeof toValue !== 'string' || !isAddress(toValue)) {
      throw new CeremonyHaltError(`${transaction.id}: resolved invalid destination ${String(toValue)}`)
    }
    return {
      to: getAddress(toValue),
      data: encodeFunctionData({ abi: [abi], args: resolvedArgs }),
      value,
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
    const receipt = await this.transport.waitForReceipt(txHash)
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

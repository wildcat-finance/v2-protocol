import { getAddress, type Address, type Hex } from 'viem'
import type { DeploymentPlan, ReceiptLike } from './types'

export interface RunStateEntry {
  txHash: Hex
  blockNumber?: number | string
  status: 'submitted' | 'mined' | 'reverted' | 'predicate-failed' | 'verified'
  resolvedAddress?: Address
}

export type RunState = Record<string, RunStateEntry>

export interface ProgressStore {
  load(): RunState
  save(state: RunState): void
}

export class MemoryProgressStore implements ProgressStore {
  private state: RunState

  constructor(initial: RunState = {}) {
    this.state = structuredClone(initial)
  }

  load(): RunState {
    return structuredClone(this.state)
  }

  save(state: RunState): void {
    this.state = structuredClone(state)
  }
}

export class LocalStorageProgressStore implements ProgressStore {
  readonly key: string

  constructor(planHash: Hex, storage: Storage = localStorage) {
    this.key = `wildcat-deploy:${planHash}`
    this.storage = storage
  }

  private readonly storage: Storage

  load(): RunState {
    const raw = this.storage.getItem(this.key)
    if (!raw) return {}
    const value: unknown = JSON.parse(raw)
    if (!value || typeof value !== 'object' || Array.isArray(value)) {
      throw new Error('Stored run state is not an object.')
    }
    return value as RunState
  }

  save(state: RunState): void {
    this.storage.setItem(this.key, serializeRunState(state))
  }

  clear(): void {
    this.storage.removeItem(this.key)
  }
}

export function receiptBlockNumber(blockNumber: bigint): number | string {
  const numeric = Number(blockNumber)
  return Number.isSafeInteger(numeric) ? numeric : blockNumber.toString()
}

export function stateEntryFromReceipt(
  receipt: ReceiptLike,
  resolvedAddress?: Address,
): RunStateEntry {
  return {
    txHash: receipt.transactionHash,
    blockNumber: receiptBlockNumber(receipt.blockNumber),
    status: receipt.status === 'success' ? 'mined' : 'reverted',
    ...(resolvedAddress ? { resolvedAddress: getAddress(resolvedAddress) } : {}),
  }
}

export function outputsFromRunState(
  plan: DeploymentPlan,
  runState: RunState,
): Map<string, Address> {
  const outputs = new Map<string, Address>()
  for (const transaction of plan.transactions) {
    if (transaction.kind !== 'deploy') continue
    const address = runState[transaction.id]?.resolvedAddress
    if (address) outputs.set(transaction.output, getAddress(address))
  }
  return outputs
}

export function assertRunStateIds(plan: DeploymentPlan, state: RunState): void {
  const ids = new Set(plan.transactions.map((transaction) => transaction.id))
  for (const id of Object.keys(state)) {
    if (!ids.has(id)) throw new Error(`Run state contains unknown transaction id: ${id}`)
  }
}

export function serializeRunState(state: RunState): string {
  return `${JSON.stringify(state, null, 2)}\n`
}

export function runStateFromBundleReceipt(
  manifest: BundleManifestInput,
  receipt: ReceiptLike,
): RunState {
  const state: RunState = {}
  for (const entry of manifest.innerTransactions) {
    state[entry.planId] = {
      txHash: receipt.transactionHash,
      blockNumber: receiptBlockNumber(receipt.blockNumber),
      status: 'verified',
      ...(entry.kind === 'deploy' && entry.precomputedAddress
        ? { resolvedAddress: getAddress(entry.precomputedAddress) }
        : {}),
    }
  }
  return state
}

interface BundleManifestInput {
  innerTransactions: Array<{
    planId: string
    kind: 'deploy' | 'call'
    precomputedAddress: Address | null
  }>
}

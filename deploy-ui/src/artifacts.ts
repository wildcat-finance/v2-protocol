import { bytesToHex, getAddress, keccak256, type Hex } from 'viem'
import type {
  BundleManifest,
  DeploymentPlan,
  ExpectedAddresses,
} from './engine/types'

export interface HashedArtifact<T> {
  name: string
  hash: Hex
  value: T
}

function parseBytes<T>(bytes: Uint8Array, name: string): HashedArtifact<T> {
  let value: T
  try {
    value = JSON.parse(new TextDecoder().decode(bytes)) as T
  } catch (error) {
    throw new Error(`${name} is not valid JSON: ${(error as Error).message}`)
  }
  return { name, hash: keccak256(bytesToHex(bytes)), value }
}

export async function readFile<T>(file: File): Promise<HashedArtifact<T>> {
  return parseBytes<T>(new Uint8Array(await file.arrayBuffer()), file.name)
}

export async function fetchArtifact<T>(url: string): Promise<HashedArtifact<T>> {
  const response = await fetch(url)
  if (!response.ok) throw new Error(`${url} returned HTTP ${response.status}.`)
  return parseBytes<T>(new Uint8Array(await response.arrayBuffer()), url)
}

export function assertPlan(value: unknown): DeploymentPlan {
  const plan = value as DeploymentPlan
  if (
    !plan ||
    plan.schemaVersion !== '1.0.0' ||
    !Number.isInteger(plan.chainId) ||
    plan.chainId < 1 ||
    plan.onFailure !== 'halt' ||
    plan.resume !== 're-verify all prior predicates before continuing' ||
    !Array.isArray(plan.transactions) ||
    plan.transactions.length === 0
  ) {
    throw new Error('Plan does not satisfy the deployment plan 1.0 identity and safety fields.')
  }
  getAddress(plan.expectedExecutor)
  const ids = new Set<string>()
  for (const transaction of plan.transactions) {
    if (!transaction.id || ids.has(transaction.id)) {
      throw new Error(`Plan has a missing or duplicate transaction id: ${transaction.id}.`)
    }
    ids.add(transaction.id)
    if (
      transaction.envelope.chainId !== plan.chainId ||
      transaction.envelope.expectedExecutor.toLowerCase() !==
        plan.expectedExecutor.toLowerCase()
    ) {
      throw new Error(`${transaction.id}: execution envelope does not match plan identity.`)
    }
  }
  return plan
}

export function assertManifest(value: unknown): BundleManifest {
  const manifest = value as BundleManifest
  if (
    !manifest ||
    manifest.schemaVersion !== '1.0.0' ||
    manifest.safe?.version !== '1.4.1' ||
    manifest.safeTransaction?.operation !== 1 ||
    !Array.isArray(manifest.innerTransactions)
  ) {
    throw new Error('Bundle manifest is missing its Safe 1.4.1 DELEGATECALL safety fields.')
  }
  return manifest
}

export function assertExpectedAddresses(value: unknown): ExpectedAddresses {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    throw new Error('expected-addresses.json must be an object.')
  }
  return Object.fromEntries(
    Object.entries(value).map(([id, address]) => [id, getAddress(String(address))]),
  )
}

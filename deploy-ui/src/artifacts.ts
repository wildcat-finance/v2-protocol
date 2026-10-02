import { bytesToHex, getAddress, keccak256, stringToHex, type Hex } from 'viem'
import type {
  BundleManifest,
  DeploymentPlan,
  ExpectedAddresses,
} from './engine/types'
import { validateBundleArtifacts } from './engine/safeCeremony'

export interface HashedArtifact<T> {
  name: string
  hash: Hex
  value: T
}

export type CeremonyMode = 'eoa' | 'safe'

interface PackagedArtifact {
  name: string
  hash: Hex
  json: string
}

interface CeremonyPackagePayload {
  mode: CeremonyMode
  release: string
  network: string
  chainId: number
  artifacts: {
    plan: PackagedArtifact
    manifests: PackagedArtifact[]
    expectedAddresses: PackagedArtifact | null
  }
}

interface CeremonyPackage {
  schemaVersion: '1.0.0'
  digest: Hex
  payload: CeremonyPackagePayload
}

export interface LoadedCeremonyPackage {
  digest: Hex
  fingerprint: string
  mode: CeremonyMode
  plan: HashedArtifact<DeploymentPlan>
  manifests: HashedArtifact<BundleManifest>[]
  expectedAddresses: HashedArtifact<ExpectedAddresses> | null
}

const NETWORK_CHAIN_IDS: Readonly<Record<string, number>> = {
  mainnet: 1,
  sepolia: 11155111,
  anvil: 31337,
}

function canonicalJson(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(',')}]`
  if (value !== null && typeof value === 'object') {
    return `{${Object.keys(value)
      .sort()
      .map((key) => `${JSON.stringify(key)}:${canonicalJson((value as Record<string, unknown>)[key])}`)
      .join(',')}}`
  }
  return JSON.stringify(value)
}

export function fingerprint(digest: Hex): string {
  return digest.slice(2, 14).toUpperCase().match(/.{1,4}/g)?.join('-') ?? digest
}

function unpackArtifact<T>(
  artifact: PackagedArtifact,
  validate: (value: unknown) => T,
): HashedArtifact<T> {
  if (
    !artifact ||
    typeof artifact.name !== 'string' ||
    typeof artifact.hash !== 'string' ||
    typeof artifact.json !== 'string'
  ) {
    throw new Error('Ceremony package contains a malformed artifact envelope.')
  }
  const hash = keccak256(stringToHex(artifact.json))
  if (hash.toLowerCase() !== artifact.hash.toLowerCase()) {
    throw new Error(`${artifact.name}: packaged bytes do not match artifact hash ${artifact.hash}.`)
  }
  let value: unknown
  try {
    value = JSON.parse(artifact.json)
  } catch (error) {
    throw new Error(`${artifact.name} is not valid packaged JSON: ${(error as Error).message}`)
  }
  return { name: artifact.name, hash, value: validate(value) }
}

export function assertCeremonyPackage(value: unknown): LoadedCeremonyPackage {
  const ceremonyPackage = value as CeremonyPackage
  if (
    !ceremonyPackage ||
    ceremonyPackage.schemaVersion !== '1.0.0' ||
    typeof ceremonyPackage.digest !== 'string' ||
    !ceremonyPackage.payload ||
    !['eoa', 'safe'].includes(ceremonyPackage.payload.mode)
  ) {
    throw new Error('Embedded ceremony package does not satisfy schema 1.0 identity fields.')
  }
  const digest = keccak256(stringToHex(canonicalJson(ceremonyPackage.payload)))
  if (digest.toLowerCase() !== ceremonyPackage.digest.toLowerCase()) {
    throw new Error(
      `Embedded ceremony digest mismatch: declared ${ceremonyPackage.digest}, compiled ${digest}.`,
    )
  }
  const plan = unpackArtifact(ceremonyPackage.payload.artifacts.plan, assertPlan)
  if (
    plan.value.release !== ceremonyPackage.payload.release ||
    plan.value.network !== ceremonyPackage.payload.network ||
    plan.value.chainId !== ceremonyPackage.payload.chainId
  ) {
    throw new Error('Ceremony package identity does not match its deployment plan.')
  }
  const manifests = ceremonyPackage.payload.artifacts.manifests.map((artifact) =>
    unpackArtifact(artifact, assertManifest),
  )
  const expectedAddresses = ceremonyPackage.payload.artifacts.expectedAddresses
    ? unpackArtifact(
        ceremonyPackage.payload.artifacts.expectedAddresses,
        assertExpectedAddresses,
      )
    : null
  if (
    (ceremonyPackage.payload.mode === 'eoa' &&
      (manifests.length !== 0 || expectedAddresses !== null)) ||
    (ceremonyPackage.payload.mode === 'safe' &&
      (manifests.length === 0 || expectedAddresses === null))
  ) {
    throw new Error('Ceremony package artifacts do not match its EOA/Safe execution mode.')
  }
  if (ceremonyPackage.payload.mode === 'eoa' && plan.value.chainId === 1) {
    throw new Error('Ethereum mainnet ceremony packages cannot use EOA mode.')
  }
  if (ceremonyPackage.payload.mode === 'safe' && expectedAddresses) {
    validateBundleArtifacts(
      plan.value,
      plan.hash,
      manifests.map((artifact) => artifact.value),
      expectedAddresses.value,
    )
  }
  return {
    digest,
    fingerprint: fingerprint(digest),
    mode: ceremonyPackage.payload.mode,
    plan,
    manifests,
    expectedAddresses,
  }
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
    plan.schemaVersion !== '1.1.0' ||
    plan.foundryProfile !== 'deploy' ||
    !Number.isInteger(plan.chainId) ||
    plan.chainId < 1 ||
    plan.onFailure !== 'halt' ||
    plan.resume !== 're-verify all prior predicates before continuing' ||
    !Array.isArray(plan.transactions) ||
    plan.transactions.length === 0
  ) {
    throw new Error('Plan does not satisfy the deployment plan 1.1 identity and safety fields.')
  }
  const configuredChainId = NETWORK_CHAIN_IDS[plan.network]
  if (configuredChainId !== undefined && plan.chainId !== configuredChainId) {
    throw new Error(
      `Plan network ${plan.network} requires chain ID ${configuredChainId}, got ${plan.chainId}.`,
    )
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
    if (
      transaction.kind === 'deploy' &&
      (!Array.isArray(transaction.constructorArgs?.types) ||
        transaction.constructorArgs.types.length !== transaction.constructorArgs.decoded.length)
    ) {
      throw new Error(`${transaction.id}: constructor ABI types are missing or incomplete.`)
    }
    if (transaction.kind === 'call') {
      const hasArgs = Array.isArray(transaction.args)
      const hasForwardedCall = transaction.forwardedCall !== undefined
      if (hasArgs === hasForwardedCall) {
        throw new Error(`${transaction.id}: call must contain exactly one of args or forwardedCall.`)
      }
      if (
        hasForwardedCall &&
        (transaction.functionSignature !== 'executeProtocolAction(address,bytes)' ||
          transaction.envelope.data !== 'forwardedCall')
      ) {
        throw new Error(`${transaction.id}: forwarded call has an invalid helper envelope.`)
      }
      if (!hasForwardedCall && transaction.envelope.data !== 'functionSignature+args') {
        throw new Error(`${transaction.id}: direct call has an invalid execution envelope.`)
      }
    }
  }
  const positions = new Map(plan.transactions.map((transaction, index) => [transaction.id, index]))
  plan.transactions.forEach((transaction, index) => {
    if (!transaction.reverifyUntil) return
    const untilIndex = positions.get(transaction.reverifyUntil)
    if (untilIndex === undefined || untilIndex <= index) {
      throw new Error(
        `${transaction.id}: reverifyUntil must name a later compensating transaction.`,
      )
    }
  })
  return plan
}

export function assertManifest(value: unknown): BundleManifest {
  const manifest = value as BundleManifest
  if (
    !manifest ||
    manifest.schemaVersion !== '1.1.0' ||
    manifest.safe?.version !== '1.4.1' ||
    manifest.safeTransaction?.operation !== 1 ||
    !Array.isArray(manifest.innerTransactions)
  ) {
    throw new Error('Bundle manifest is missing its nonce-pinned Safe 1.4.1 DELEGATECALL safety fields.')
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

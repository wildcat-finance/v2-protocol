import {
  useEffect,
  useMemo,
  useRef,
  useState,
  type CSSProperties,
  type KeyboardEvent as ReactKeyboardEvent,
  type PointerEvent as ReactPointerEvent,
  type ReactNode,
} from 'react'
import { useAccount, useConnect, useDisconnect } from 'wagmi'
import { formatEther, keccak256 } from 'viem'
import type { Address, Hex } from 'viem'
import {
  assertCeremonyPackage,
  assertExpectedAddresses,
  assertManifest,
  assertPlan,
  fetchArtifact,
  fingerprint,
  readFile,
  type HashedArtifact,
  type LoadedCeremonyPackage,
} from './artifacts'
import { CeremonyHaltError, PlanExecutor, type PreparedTransaction } from './engine/planExecutor'
import { LocalStorageProgressStore, type RunState, type RunStateEntry } from './engine/runState'
import { SafeCeremony, type SignatureProgress } from './engine/safeCeremony'
import type {
  BundleManifest,
  DeploymentPlan,
  ExpectedAddresses,
  PlanTransaction,
  PlanValue,
  Predicate,
} from './engine/types'
import { browserExecutionTransport, injectedProvider } from './walletTransport'
import { SAFE_1_4_1_FORK_NETWORKS } from './safeContracts'
import {
  clampRailWidth,
  DEFAULT_RAIL_WIDTH,
  eoaCompletionGuidance,
  errorText,
  isRpcUnavailableError,
  shortErrorText,
  MAX_RAIL_WIDTH,
  MIN_RAIL_WIDTH,
  needsAnvilResumeDecision,
  runStateForDisplay,
} from './uiState'

export type Mode = 'eoa' | 'safe'

interface StatusMessage {
  tone: 'ok' | 'info' | 'warn'
  text: string
  code?: string
  detail?: string
}

const embeddedRelease: { value: LoadedCeremonyPackage | null; error: string } = (() => {
  if (__CEREMONY_PACKAGE__ === null) return { value: null, error: '' }
  try {
    return { value: assertCeremonyPackage(__CEREMONY_PACKAGE__), error: '' }
  } catch (error) {
    return {
      value: null,
      error: `Embedded release package is invalid: ${error instanceof Error ? error.message : String(error)}`,
    }
  }
})()

const numberFormat = new Intl.NumberFormat('en-US')

function short(value: string): string {
  return value.length > 18 ? `${value.slice(0, 10)}…${value.slice(-6)}` : value
}

function contractName(artifactName: string): string {
  return artifactName.split(':').pop() ?? artifactName
}

function retirementAddress(description: string): string | null {
  return description.match(/0x[0-9a-fA-F]{40}/)?.[0] ?? null
}

function firstSentence(text: string): string {
  const end = text.indexOf('. ')
  return (end === -1 ? text : text.slice(0, end)).replace(/\.$/, '')
}

export function friendlyLabel(description: string, planId?: string): string {
  const address = retirementAddress(description)
  if (address && planId?.startsWith('remove-superseded-controller-factory-')) {
    return `Block factory ${short(address)}`
  }
  if (address && planId?.startsWith('remove-superseded-controller-')) {
    return `Block new markets ${short(address)}`
  }
  return firstSentence(description)
    .replace(' the v2.5 ', ' ')
    .replace(' for this deployment', '')
}

function plainDescription(description: string, planId: string): string {
  if (planId.startsWith('remove-superseded-controller-factory-')) {
    return 'Prevent this superseded hooks factory from re-registering as a controller'
  }
  if (planId.startsWith('remove-superseded-controller-')) {
    return 'Prevent this superseded hooks factory from registering new markets'
  }
  return description.replace(' the v2.5 ', ' ').replace(/\.$/, '')
}

// Plan IDs follow `verb-subject[-qualifier]` and stay stable across ceremonies, while
// descriptions are rewritten by every new generator, so step labels come from the ID.
export function stepLabel(planId: string, description: string): string {
  if (planId.startsWith('remove-superseded-controller')) return friendlyLabel(description, planId)
  const [verb, ...words] = planId.split('-')
  if (words.length === 0) return friendlyLabel(description, planId)
  const qualifiers = words.filter((word) => word === 'standard' || word === 'revolving')
  const subject = words
    .filter((word) => word !== 'standard' && word !== 'revolving')
    .join(' ')
    .replace(/\binit code storage secondary\b/, 'code (secondary)')
    .replace(/\binit code storage\b/, 'code')
    .replace(
      /\b(open|fixed|periodic) term(?: hooks)?\b/,
      (_, kind: string) => `${kind[0].toUpperCase()}${kind.slice(1)}TermHooks`,
    )
    .replace(/\bwildcat 4626\b/, 'ERC-4626')
    .replace(/\bwildcat market\b/, 'WildcatMarket')
    .replace(/\bmarket lens\b/, 'MarketLens')
    .replace(/\barch controller\b/, 'ArchController')
    .replace(/\bspherex\b/g, 'SphereX')
    .replace(/\berc(\d+)\b/, 'ERC-$1')
    .replace(/(.) template$/, '$1')
  const qualifier = qualifiers.length > 0 ? ` · ${qualifiers.join(' ')}` : ''
  return `${verb === 'add' ? 'register' : verb}: ${subject}${qualifier}`
}

function descriptionParts(description: string, planId: string): [string, string] {
  const plain = plainDescription(description, planId)
  const end = plain.indexOf('. ')
  return end === -1 ? [plain, ''] : [plain.slice(0, end), `${plain.slice(end + 2)}.`]
}

function functionName(signature: string): string {
  return signature.split('(')[0]
}

export function transactionValueLabel(value: string): string {
  const wei = BigInt(value)
  return wei === 0n ? '0 ETH' : `${formatEther(wei)} ETH`
}

function plainPredicateResult(predicate: Predicate): string {
  if (predicate.type === 'splitCodeHash') {
    return 'Both storage contracts, their link, and the recovered creation code must match the reviewed artifacts.'
  }
  if (predicate.type === 'codeHash') {
    return predicate.initCodeHash
      ? 'The stored code and recovered creation code must match the reviewed artifact.'
      : 'The stored code must match the reviewed artifact.'
  }
  if (predicate.type === 'codePresent') {
    return 'The new contract must be present at its recorded address.'
  }
  const call = functionName(predicate.call.sig)
  const expected = predicate.expect
  if (call === 'owner') return 'Ownership must match the reviewed destination.'
  if (call === 'v1Factory') return 'The wrapper must point to the reviewed V1 factory.'
  if (call === 'marketInitCodeStorage') {
    return 'The factory must point to the newly deployed market code.'
  }
  if (call === 'hooksFactory') {
    return 'The lens component must point to the newly deployed standard hooks factory.'
  }
  if (call === 'aggregationHelper') {
    return 'The lens facade must point to its newly deployed aggregation helper.'
  }
  if (call === 'isHooksTemplate') {
    return expected === true
      ? 'The hooks template must be registered with the reviewed factory.'
      : 'The hooks template must not be registered with the reviewed factory.'
  }
  if (call === 'isRegisteredControllerFactory') {
    return expected === true
      ? 'The factory must be authorized to register controllers.'
      : 'The superseded factory must no longer be authorized to register controllers.'
  }
  if (call === 'isRegisteredController') {
    return expected === true
      ? 'The hooks factory must be authorized to register markets.'
      : 'The superseded factory must no longer be authorized to register markets.'
  }
  if (call === 'getHooksTemplateInitCodeHash') {
    return 'The factory must record the reviewed creation-code hash for this template.'
  }
  if (call === 'getHooksTemplateDetails') {
    return 'The template’s recorded factory settings must match the reviewed values exactly.'
  }
  return 'The resulting on-chain state must match the reviewed release plan.'
}

function isReference(value: PlanValue | undefined): value is { $ref: string } {
  return typeof value === 'object' && value !== null && !Array.isArray(value) && '$ref' in value
}

function isAddressString(value: string): boolean {
  return /^0x[0-9a-fA-F]{40}$/.test(value)
}

function isHashString(value: string): boolean {
  return /^0x[0-9a-fA-F]{64}$/.test(value)
}

function isBytesBlob(value: string): boolean {
  return /^0x[0-9a-fA-F]*$/.test(value) && value.length > 66
}

function decodedValues(transaction: PlanTransaction): PlanValue[] {
  if (transaction.kind === 'deploy') return transaction.constructorArgs.decoded
  return transaction.forwardedCall?.args ?? transaction.args ?? []
}

function parseSignatureTypes(signature: string, count: number): string[] {
  const open = signature.indexOf('(')
  const close = signature.lastIndexOf(')')
  if (open === -1 || close <= open) return Array<string>(count).fill('')
  const inner = signature.slice(open + 1, close).trim()
  if (!inner) return []
  const types = inner.split(',').map((part) => part.trim())
  return types.length === count ? types : Array<string>(count).fill('')
}

interface RailGroup {
  title: string
  start: number
  count: number
}

function groupPlan(plan: DeploymentPlan): RailGroup[] {
  const label = (transaction: PlanTransaction): string => {
    if (transaction.id.startsWith('reclaim-')) return 'Take ownership'
    if (transaction.id.startsWith('restore-')) return 'Return ownership'
    if (transaction.kind === 'deploy') return 'Deploy contracts'
    if (transaction.id.startsWith('remove-') || transaction.id.startsWith('disable-')) {
      return 'Retire superseded'
    }
    if (transaction.id.startsWith('register-') || transaction.id.startsWith('add-')) {
      return 'Register & wire'
    }
    return 'Steps'
  }
  const groups: RailGroup[] = []
  plan.transactions.forEach((transaction, index) => {
    const title = label(transaction)
    const last = groups[groups.length - 1]
    if (last && last.title === title) last.count += 1
    else groups.push({ title, start: index, count: 1 })
  })
  return groups
}

interface KeccakXrefs {
  blobHash: Map<string, number>
  hashUse: Map<string, number>
}

function buildKeccakXrefs(plan: DeploymentPlan): KeccakXrefs {
  const blobHash = new Map<string, number>()
  plan.transactions.forEach((transaction, index) => {
    for (const value of decodedValues(transaction)) {
      if (typeof value === 'string' && isBytesBlob(value)) {
        blobHash.set(keccak256(value as Hex).toLowerCase(), index)
      }
    }
  })
  const hashUse = new Map<string, number>()
  plan.transactions.forEach((transaction, index) => {
    for (const value of decodedValues(transaction)) {
      if (
        typeof value === 'string' &&
        isHashString(value) &&
        blobHash.has(value.toLowerCase()) &&
        blobHash.get(value.toLowerCase()) !== index
      ) {
        hashUse.set(value.toLowerCase(), index)
      }
    }
  })
  return { blobHash, hashUse }
}

function saveJson(name: string, state: RunState): void {
  const blob = new Blob([`${JSON.stringify(state, null, 2)}\n`], {
    type: 'application/json',
  })
  const link = document.createElement('a')
  link.href = URL.createObjectURL(blob)
  link.download = name
  link.click()
  URL.revokeObjectURL(link.href)
}

export function ExecutionIdentity({
  mode,
  actionCount,
  bundleCount,
  expectedExecutor,
  safeVersion,
}: {
  mode: Mode
  actionCount: number
  bundleCount: number
  expectedExecutor: Address
  safeVersion?: string
}) {
  const summary =
    mode === 'eoa'
      ? `${actionCount} individual transactions`
      : `${bundleCount} bundle${bundleCount === 1 ? '' : 's'} · ${actionCount} actions`
  const authority =
    mode === 'eoa' ? 'Expected EOA' : `Expected Safe${safeVersion ? ` v${safeVersion}` : ''}`
  return (
    <span
      className={`chip execution ${mode}`}
      title={`${summary} · ${authority}: ${expectedExecutor}`}
      role="group"
      aria-label={`${mode === 'eoa' ? 'EOA' : 'Safe'} execution: ${summary}; ${authority} ${expectedExecutor}`}
    >
      <strong>{mode === 'eoa' ? 'EOA' : 'SAFE'}</strong>
      <span className="lt">· {mode === 'eoa' ? `${actionCount} tx` : summary}</span>
      {mode === 'safe' ? (
        <code>
          · {safeVersion ? `v${safeVersion} · ` : ''}
          {short(expectedExecutor)}
        </code>
      ) : null}
    </span>
  )
}

export function CeremonyProgress({
  mode,
  activeEoaIndex,
  actionCount,
  verifiedActions,
  bundleCount,
  completedBundles,
  signatureProgress,
  safeThreshold,
}: {
  mode: Mode
  activeEoaIndex: number
  actionCount: number
  verifiedActions: number
  bundleCount: number
  completedBundles: number
  signatureProgress: SignatureProgress | null
  safeThreshold: number | null
}) {
  if (mode === 'safe' && bundleCount === 0) {
    return (
      <span className="meter" role="status" aria-label="Safe bundles are not loaded">
        <span className="metric-key">BUNDLES</span> <b>not loaded</b>
      </span>
    )
  }
  const current =
    mode === 'eoa'
      ? Math.min(activeEoaIndex + 1, actionCount)
      : Math.min(completedBundles + 1, bundleCount)
  const complete = mode === 'eoa' ? verifiedActions === actionCount : completedBundles === bundleCount
  const unitCount = mode === 'eoa' ? actionCount : bundleCount
  const threshold = signatureProgress?.threshold ?? safeThreshold
  const signatureLabel = complete
    ? `executed${threshold ? ` · threshold ${threshold}` : ''}`
    : signatureProgress
      ? `${signatureProgress.confirmations}/${signatureProgress.threshold} signatures`
      : threshold
        ? `threshold ${threshold}`
        : 'threshold —'
  const label =
    mode === 'eoa'
      ? `Transaction ${current} of ${actionCount}; ${verifiedActions} of ${actionCount} checks passed`
      : `Bundle ${current} of ${bundleCount}; ${signatureLabel}; ${verifiedActions} of ${actionCount} checks passed`
  return (
    <span className="meter" role="status" aria-live="polite" aria-label={label} title={label}>
      <span className="meter-copy">
        <span>
          <span className="metric-key">{mode === 'eoa' ? 'TX' : 'BUNDLE'}</span>{' '}
          <b>{complete ? unitCount : current}</b>/{unitCount}
        </span>
        <span className="metric-sub">
          · {mode === 'safe' ? `${signatureLabel} · ` : ''}
          {verifiedActions}/{actionCount} checks
        </span>
      </span>
    </span>
  )
}

function ProgressSegments({
  groups,
  activeGroup,
  complete,
}: {
  groups: RailGroupModel[]
  activeGroup: number
  complete: boolean
}) {
  return (
    <div className={`segments${complete ? ' complete' : ''}`} aria-hidden="true">
      {groups.map((group, groupIndex) => (
        <span className="seg-group" key={groupIndex} style={{ flexGrow: group.rows.length }}>
          {group.rows.map((row) => (
            <i
              key={row.key}
              className={row.status === 'todo' && groupIndex === activeGroup ? 'now' : row.status}
            />
          ))}
        </span>
      ))}
    </div>
  )
}

function FingerprintBand({ digest }: { digest: string }) {
  // Twelve well-separated hues from the digest bytes after the spoken fingerprint.
  const bytes = digest.slice(14, 30).match(/.{2}/g) ?? []
  return (
    <span className="fp-band" aria-hidden="true">
      {bytes.map((byte, index) => (
        <i key={index} style={{ background: `hsl(${(parseInt(byte, 16) % 12) * 30} 62% 56%)` }} />
      ))}
    </span>
  )
}

function BlockHeartbeat({ block }: { block: { number: bigint; ok: boolean } }) {
  return (
    <span
      className={`block${block.ok ? '' : ' stale'}`}
      title={block.ok ? 'Latest block from the wallet’s RPC' : 'The wallet’s RPC is not answering'}
    >
      <i key={block.number.toString()} />
      {block.ok ? 'block' : 'RPC?'} <b>{numberFormat.format(block.number)}</b>
    </span>
  )
}

function CompletionReceipt({ plan, runState }: { plan: DeploymentPlan; runState: RunState }) {
  const steps = plan.transactions.map((transaction, index) => ({
    transaction,
    index,
    entry: runState[transaction.id],
  }))
  const deployed = steps.filter(({ entry }) => entry?.resolvedAddress).length
  const blocks = steps
    .map(({ entry }) => Number(entry?.blockNumber))
    .filter((block) => Number.isFinite(block))
  return (
    <details className="tech receipt">
      <summary>
        {deployed} deployed · {steps.length} transactions
        {blocks.length > 0
          ? ` · blocks ${numberFormat.format(Math.min(...blocks))}–${numberFormat.format(Math.max(...blocks))}`
          : ''}
      </summary>
      <div className="tech-in">
        <table className="argt">
          <tbody>
            {steps.map(({ transaction, index, entry }) => (
              <tr key={transaction.id}>
                <td className="an">{String(index + 1).padStart(2, '0')}</td>
                <td>{stepLabel(transaction.id, transaction.description)}</td>
                <td>
                  {entry ? (
                    <>
                      <code title={entry.txHash}>{short(entry.txHash)}</code>
                      <CopyButton value={entry.txHash} />
                    </>
                  ) : null}
                </td>
                <td>{entry?.resolvedAddress ? <AddressValue value={entry.resolvedAddress} /> : null}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </details>
  )
}

function haltGuidance(message: string): { heading: string; summary: string } {
  if (/has no receipt yet/i.test(message)) {
    return {
      heading: 'Do not resend.',
      summary:
        'A transaction from this ceremony was sent but has not been mined. Wait until it is mined, then reload this page to resume.',
    }
  }
  if (/prior predicate failed|fails its predicate/i.test(message)) {
    return {
      heading: 'Do not continue.',
      summary:
        'A step that already passed no longer matches the chain. Check the wallet’s network and RPC; if they are right, stop and investigate.',
    }
  }
  if (/predicate failed/i.test(message)) {
    return {
      heading: 'Do not continue.',
      summary: 'The transaction mined, but its on-chain check does not match the reviewed plan.',
    }
  }
  if (/reverted/i.test(message)) {
    return {
      heading: 'Do not continue.',
      summary: 'The transaction was mined and reverted, so none of its changes took effect.',
    }
  }
  if (/non-contiguous|unknown transaction id|does not match its receipt|lacks contractAddress|stored run state/i.test(message)) {
    return {
      heading: 'Do not continue.',
      summary:
        'The progress saved in this browser does not match this package or the chain. Export it for review; do not edit it by hand.',
    }
  }
  if (/embedded (?:release|ceremony) package|digest mismatch/i.test(message)) {
    return {
      heading: 'Do not use this build.',
      summary: 'The embedded ceremony package failed verification. Rebuild it from the reviewed package.',
    }
  }
  return {
    heading: 'Do not continue.',
    summary: 'The ceremony stopped at a check it cannot pass safely.',
  }
}

export function CeremonyHaltScreen({
  message,
  plan,
  mode,
  callFingerprint,
  runState,
  compensationId,
  haltedId,
  digest,
  at,
}: {
  message: string
  plan: DeploymentPlan | null
  mode: Mode
  callFingerprint: string | null
  runState: RunState
  compensationId?: string
  haltedId?: string
  digest?: string
  at?: Date
}) {
  const [copied, setCopied] = useState<'copied' | 'failed' | null>(null)
  const canExport = plan !== null && Object.keys(runState).length > 0
  const guidance = haltGuidance(message)
  const total = plan?.transactions.length ?? 0
  const haltedIndex = plan && haltedId ? plan.transactions.findIndex((step) => step.id === haltedId) : -1
  const halted = plan && haltedIndex >= 0 ? plan.transactions[haltedIndex] : undefined
  const verified = plan
    ? plan.transactions.filter((step) => runState[step.id]?.status === 'verified')
    : []
  const lastVerified = verified.length > 0 ? runState[verified[verified.length - 1].id] : undefined
  const report = [
    'Wildcat deploy ceremony halted',
    plan ? `release: ${plan.release} · ${plan.network} (${plan.chainId}) · ${mode.toUpperCase()}` : '',
    callFingerprint ? `fingerprint: ${callFingerprint}` : '',
    digest ? `digest: ${digest}` : '',
    at ? `time: ${at.toISOString()}` : '',
    halted ? `stopped at: transaction ${haltedIndex + 1} of ${total} (${halted.id})` : '',
    plan ? `progress: ${verified.length} of ${total} verified` : '',
    `error: ${message}`,
  ]
    .filter(Boolean)
    .join('\n')
  return (
    <main className="fatal-screen">
      <p className="eyebrow">CEREMONY HALTED</p>
      {plan ? (
        <p className="fatal-identity">
          {plan.release} · {plan.network} · {mode.toUpperCase()}
          {callFingerprint ? ` · FP ${callFingerprint}` : ''}
        </p>
      ) : null}
      <h1>{guidance.heading}</h1>
      <p className="fatal-summary">{guidance.summary}</p>
      {plan ? (
        <dl className="fatal-facts">
          {halted ? (
            <>
              <dt>stopped at</dt>
              <dd>
                Transaction {haltedIndex + 1} of {total} — {stepLabel(halted.id, halted.description)}
                <span> · </span>
                <code>{halted.id}</code>
              </dd>
            </>
          ) : null}
          <dt>progress</dt>
          <dd>
            {verified.length} of {total} verified
            {lastVerified ? (
              <>
                {' · last tx '}
                <code>{lastVerified.txHash}</code>
              </>
            ) : null}
          </dd>
          {at ? (
            <>
              <dt>time</dt>
              <dd>
                {at.toLocaleString()} <span>({at.toISOString()})</span>
              </dd>
            </>
          ) : null}
        </dl>
      ) : null}
      <pre>{message}</pre>
      <p>Preserve the loaded package, this error, and the run state. There is no skip button.</p>
      <div className="fatal-actions">
        <button
          className="fatal-export"
          onClick={() => plan && saveJson(`run-state-${plan.release}.json`, runState)}
          disabled={!canExport}
        >
          Export run state
        </button>
        <button
          className="fatal-copy"
          onClick={() => {
            void copyText(report).then((ok) => {
              setCopied(ok ? 'copied' : 'failed')
              window.setTimeout(() => setCopied(null), 1500)
            })
          }}
        >
          {copied === 'copied' ? 'Copied' : copied === 'failed' ? 'Copy failed' : 'Copy error report'}
        </button>
        {!canExport ? <span>No completed transaction state is available yet.</span> : null}
      </div>
      {compensationId ? (
        <p>
          Temporary ownership may still be held by the ceremony executor. Before ending the
          session, use the reviewed recovery procedure to execute <code>{compensationId}</code> and
          confirm its predicate.
        </p>
      ) : null}
    </main>
  )
}

function copyText(value: string): Promise<boolean> {
  // navigator.clipboard exists only in secure contexts; a CEREMONY_HOST LAN origin is plain HTTP.
  const fallback = (): boolean => {
    const area = document.createElement('textarea')
    area.value = value
    area.setAttribute('readonly', '')
    area.style.position = 'fixed'
    area.style.opacity = '0'
    document.body.append(area)
    area.select()
    try {
      return document.execCommand('copy')
    } catch {
      return false
    } finally {
      area.remove()
    }
  }
  if (!navigator.clipboard) return Promise.resolve(fallback())
  return navigator.clipboard.writeText(value).then(() => true, fallback)
}

function CopyButton({ value }: { value: string }) {
  const [result, setResult] = useState<'copied' | 'failed' | null>(null)
  return (
    <button
      type="button"
      className={`copy${result ? ` ${result}` : ''}`}
      title={result === 'failed' ? 'Copy failed — select the value instead' : 'Copy full value'}
      aria-label="Copy full value"
      onClick={() => {
        void copyText(value).then((copied) => {
          setResult(copied ? 'copied' : 'failed')
          window.setTimeout(() => setResult(null), 1200)
        })
      }}
    >
      <svg viewBox="0 0 16 16" width="12" height="12" aria-hidden="true">
        {result === 'copied' ? (
          <path d="M3 8.5l3.2 3L13 4.5" />
        ) : result === 'failed' ? (
          <path d="M4 4l8 8M12 4l-8 8" />
        ) : (
          <>
            <rect x="5.5" y="5.5" width="8" height="8" rx="1.5" />
            <path d="M10.5 3.5V3A1.5 1.5 0 0 0 9 1.5H4A1.5 1.5 0 0 0 2.5 3v5A1.5 1.5 0 0 0 4 9.5h.5" />
          </>
        )}
      </svg>
    </button>
  )
}

function AddressValue({ value }: { value: string }) {
  return (
    <span className="addr">
      <code title={value}>{short(value)}</code>
      <CopyButton value={value} />
    </span>
  )
}

function HexChunks({ value }: { value: string }) {
  return (
    <code className="hexchunks" title={value}>
      <span>0x</span>
      {value
        .slice(2)
        .match(/.{1,4}/g)
        ?.map((chunk, index) => <span key={index}>{chunk}</span>)}
    </code>
  )
}

function RefValue({ reference, outputs }: { reference: string; outputs: Map<string, Address> }) {
  const resolved = outputs.get(reference)
  return (
    <span
      className="refc"
      title={resolved ?? 'plan reference — resolves when the producing deploy is verified'}
    >
      → {reference}
      {resolved ? <span className="ra"> {short(resolved)}</span> : null}
    </span>
  )
}

function BytesValue({
  value,
  xrefs,
  stepIndex,
}: {
  value: Hex
  xrefs?: KeccakXrefs
  stepIndex?: number
}) {
  const [open, setOpen] = useState(false)
  const hash = useMemo(() => keccak256(value), [value])
  const reuse = xrefs?.hashUse.get(hash.toLowerCase())
  return (
    <>
      <span className="byteschip">
        <span className="sz">{numberFormat.format((value.length - 2) / 2)} bytes</span>
        <code title={`keccak256 ${hash}`}>keccak256 {short(hash)}</code>
        <CopyButton value={hash} />
        <button className="mini" onClick={() => setOpen(!open)}>
          {open ? 'hide bytes' : 'show bytes'}
        </button>
      </span>
      {reuse !== undefined && reuse !== stepIndex ? (
        <span className="xref">keccak256 reappears as an argument in step {reuse + 1}</span>
      ) : null}
      {open ? <pre className="bytes-full">{value}</pre> : null}
    </>
  )
}

function ArgValue({
  value,
  outputs,
  xrefs,
  stepIndex,
}: {
  value: PlanValue
  outputs: Map<string, Address>
  xrefs?: KeccakXrefs
  stepIndex?: number
}) {
  if (isReference(value)) return <RefValue reference={value.$ref} outputs={outputs} />
  if (typeof value === 'string') {
    if (isBytesBlob(value)) {
      return <BytesValue value={value as Hex} xrefs={xrefs} stepIndex={stepIndex} />
    }
    if (isAddressString(value)) return <AddressValue value={value} />
    if (isHashString(value)) {
      const blobIndex = xrefs?.blobHash.get(value.toLowerCase())
      return (
        <>
          <code title={value}>{short(value)}</code>
          <CopyButton value={value} />
          {blobIndex !== undefined && blobIndex !== stepIndex ? (
            <span className="xref">
              equals keccak256 of the bytes argument in step {blobIndex + 1}
            </span>
          ) : null}
        </>
      )
    }
    return <code>{JSON.stringify(value)}</code>
  }
  if (typeof value === 'number' || typeof value === 'boolean' || value === null) {
    return <code>{String(value)}</code>
  }
  const json = JSON.stringify(value)
  return <code title={json}>{json.length > 64 ? `${json.slice(0, 61)}…` : json}</code>
}

function ArgsTable({
  transaction,
  stepIndex,
  outputs,
  xrefs,
}: {
  transaction: PlanTransaction
  stepIndex: number
  outputs: Map<string, Address>
  xrefs: KeccakXrefs
}) {
  const values = decodedValues(transaction)
  if (values.length === 0) return <span className="none">no arguments</span>
  const types =
    transaction.kind === 'deploy'
      ? transaction.constructorArgs.types
      : parseSignatureTypes(
          transaction.forwardedCall?.functionSignature ?? transaction.functionSignature,
          values.length,
        )
  return (
    <table className="argt">
      <thead>
        <tr>
          <th>#</th>
          <th>type</th>
          <th>value</th>
        </tr>
      </thead>
      <tbody>
        {values.map((value, argIndex) => (
          <tr key={argIndex}>
            <td className="an">{argIndex + 1}</td>
            <td className="at">{types[argIndex] ?? ''}</td>
            <td>
              <ArgValue value={value} outputs={outputs} xrefs={xrefs} stepIndex={stepIndex} />
            </td>
          </tr>
        ))}
      </tbody>
    </table>
  )
}

function TargetValue({
  target,
  outputs,
}: {
  target: Address | { $ref: string }
  outputs: Map<string, Address>
}) {
  if (isReference(target)) return <RefValue reference={target.$ref} outputs={outputs} />
  return <AddressValue value={target} />
}

function inlineValue(value: PlanValue, outputs: Map<string, Address>): string {
  if (isReference(value)) {
    const resolved = outputs.get(value.$ref)
    return `→${value.$ref}${resolved ? ` (${short(resolved)})` : ''}`
  }
  if (typeof value === 'string') return isAddressString(value) ? short(value) : value
  return String(value)
}

function returnTypes(signature: string): string[] {
  const returns = signature.match(/returns\s*\((.*)\)\s*$/)?.[1]?.trim()
  if (!returns) return []
  const inner = returns.startsWith('(') && returns.endsWith(')') ? returns.slice(1, -1) : returns
  const types: string[] = []
  let depth = 0
  let current = ''
  for (const char of inner) {
    if (char === ',' && depth === 0) {
      types.push(current.trim())
      current = ''
      continue
    }
    if (char === '(') depth += 1
    if (char === ')') depth -= 1
    current += char
  }
  if (current.trim()) types.push(current.trim())
  return types
}

function ExpectedValue({
  value,
  outputs,
  types = [],
}: {
  value: PlanValue
  outputs: Map<string, Address>
  types?: string[]
}) {
  if (isReference(value)) return <RefValue reference={value.$ref} outputs={outputs} />
  if (typeof value === 'string' && isAddressString(value)) return <AddressValue value={value} />
  if (typeof value === 'string' && isHashString(value)) return <HexChunks value={value} />
  if (Array.isArray(value)) {
    return (
      <ol className="tuple">
        {value.map((item, index) => (
          <li key={index}>
            <span className="ty">{types.length === value.length ? types[index] : `[${index}]`}</span>
            <ExpectedValue value={item} outputs={outputs} />
          </li>
        ))}
      </ol>
    )
  }
  return <code>{JSON.stringify(value)}</code>
}

function CheckAssertion({
  predicate,
  outputs,
  verified,
}: {
  predicate: Predicate
  outputs: Map<string, Address>
  verified: boolean
}) {
  const mark = verified ? <span className="okmark"> ✓</span> : null
  if (predicate.type === 'codePresent') {
    return (
      <div className="assert">
        <div className="assert-head">
          code present at <TargetValue target={predicate.target} outputs={outputs} />
          {mark}
        </div>
      </div>
    )
  }
  if (predicate.type === 'codeHash' || predicate.type === 'splitCodeHash') {
    return (
      <div className="assert">
        <div className="assert-head">
          {predicate.type === 'splitCodeHash' ? 'unlinked primary code hash at ' : 'code hash at '}
          <TargetValue target={predicate.target} outputs={outputs} />
          {mark}
        </div>
        <dl className="assert-rows">
          <dt>expected</dt>
          <dd>
            <HexChunks value={predicate.expect} />
          </dd>
          {predicate.type === 'splitCodeHash' ? (
            <>
              <dt>secondary link</dt>
              <dd>
                <TargetValue target={predicate.secondary} outputs={outputs} />
              </dd>
              <dt>secondary code</dt>
              <dd>
                <HexChunks value={predicate.secondaryCodeHash} />
              </dd>
            </>
          ) : null}
          {predicate.initCodeHash ? (
            <>
              <dt>creation code</dt>
              <dd>
                <HexChunks value={predicate.initCodeHash} />
              </dd>
            </>
          ) : null}
        </dl>
      </div>
    )
  }
  const args = predicate.call.args.map((value) => inlineValue(value, outputs)).join(', ')
  return (
    <div className="assert">
      <div className="assert-head">
        <TargetValue target={predicate.target} outputs={outputs} /> . {functionName(predicate.call.sig)}
        ({args}){predicate.type === 'callResultEq' ? `[${predicate.resultIndex}]` : null}
        {mark}
      </div>
      <dl className="assert-rows">
        <dt>expected</dt>
        <dd>
          <ExpectedValue
            value={predicate.expect}
            outputs={outputs}
            types={predicate.type === 'callEq' ? returnTypes(predicate.call.sig) : []}
          />
        </dd>
      </dl>
    </div>
  )
}

function StatusPill({ status }: { status?: string }) {
  return <span className={`pill ${status || 'waiting'}`}>{status || 'waiting'}</span>
}

interface RailRowModel {
  key: string
  number: number
  label: string
  title: string
  status: 'done' | 'now' | 'todo' | 'fail'
  selectIndex: number
}

interface RailGroupModel {
  title: string
  detail?: string
  rows: RailRowModel[]
}

function Rail({
  groups,
  selectedIndex,
  onSelect,
  head,
  footer,
}: {
  groups: RailGroupModel[]
  selectedIndex: number
  onSelect: (index: number) => void
  head: ReactNode
  footer: ReactNode
}) {
  const railRef = useRef<HTMLElement | null>(null)
  useEffect(() => {
    const rail = railRef.current
    const row = rail?.querySelector<HTMLElement>('.row.sel')
    if (!rail || !row) return
    const railBox = rail.getBoundingClientRect()
    const rowBox = row.getBoundingClientRect()
    if (rowBox.top < railBox.top) rail.scrollTop -= railBox.top - rowBox.top + 12
    else if (rowBox.bottom > railBox.bottom) rail.scrollTop += rowBox.bottom - railBox.bottom + 12
  }, [selectedIndex])
  return (
    <nav className="rail" aria-label="Ceremony steps" ref={railRef}>
      {head ? <div className="rail-head">{head}</div> : null}
      {groups.map((group, groupIndex) => (
        <div className="grp" key={groupIndex}>
          <div className="grp-h">
            <span>
              {group.title}
              {group.detail ? <span className="gc"> {group.detail}</span> : null}
            </span>
            <span className="gc">{group.rows.length}</span>
          </div>
          {group.rows.map((row) => (
            <button
              key={row.key}
              className={`row ${row.status}${row.selectIndex === selectedIndex ? ' sel' : ''}`}
              title={row.title}
              onClick={() => onSelect(row.selectIndex)}
            >
              <span className="dot"></span>
              <span className="rn">{String(row.number).padStart(2, '0')}</span>
              <span className="rid">{row.label}</span>
            </button>
          ))}
        </div>
      ))}
      <div className="legend">
        <span>
          <i className="l-done"></i>verified
        </span>
        <span>
          <i className="l-now"></i>up next
        </span>
        <span>
          <i className="l-todo"></i>queued
        </span>
        <span className="keys">
          <kbd>j</kbd>
          <kbd>k</kbd> browse · <kbd>Enter</kbd> current step
        </span>
      </div>
      <div className="fineprint">{footer}</div>
    </nav>
  )
}

function StateStrip({
  entry,
  isActive,
  activeNote,
  blocked,
  queuedBehind,
}: {
  entry: RunStateEntry | undefined
  isActive: boolean
  activeNote: string
  blocked: string | null
  queuedBehind: number | null
}) {
  if (entry?.status === 'verified') {
    return (
      <div className="state-strip done">
        ✓ VERIFIED{' '}
        <span className="sans">
          tx <code title={entry.txHash}>{short(entry.txHash)}</code>
          {entry.blockNumber !== undefined ? ` · block ${numberFormat.format(Number(entry.blockNumber))}` : ''}
          {entry.resolvedAddress ? (
            <>
              {' · deployed at '}
              <code title={entry.resolvedAddress}>{short(entry.resolvedAddress)}</code>
            </>
          ) : null}
        </span>
      </div>
    )
  }
  if (entry && (entry.status === 'reverted' || entry.status === 'predicate-failed')) {
    return (
      <div className="state-strip fail">
        ✕ {entry.status.toUpperCase()}{' '}
        <span className="sans">
          tx <code title={entry.txHash}>{short(entry.txHash)}</code> — the ceremony is halted.
        </span>
      </div>
    )
  }
  if (isActive && blocked) {
    return (
      <div className="state-strip blocked">
        ■ BLOCKED <span className="sans">{blocked}</span>
      </div>
    )
  }
  if (isActive) {
    return (
      <div className="state-strip now">
        ▶ UP NEXT <span className="sans">{activeNote}</span>
      </div>
    )
  }
  return (
    <div className="state-strip">
      ○ QUEUED{' '}
      <span className="sans">
        {queuedBehind !== null && queuedBehind > 0
          ? `${queuedBehind} step${queuedBehind > 1 ? 's' : ''} ahead of this one. Shown for review only.`
          : 'shown for review only.'}
      </span>
    </div>
  )
}

export default function App() {
  const { address, chainId, isConnected } = useAccount()
  const { connectors, connect, isPending: connecting } = useConnect()
  const { disconnect } = useDisconnect()
  const [mode, setMode] = useState<Mode>(embeddedRelease.value?.mode ?? 'eoa')
  const [planArtifact, setPlanArtifact] = useState<HashedArtifact<DeploymentPlan> | null>(
    embeddedRelease.value?.plan ?? null,
  )
  const [manifestArtifacts, setManifestArtifacts] = useState<HashedArtifact<BundleManifest>[]>(
    embeddedRelease.value?.manifests ?? [],
  )
  const [expectedArtifact, setExpectedArtifact] = useState<HashedArtifact<ExpectedAddresses> | null>(
    embeddedRelease.value?.expectedAddresses ?? null,
  )
  const [message, setMessage] = useState<StatusMessage | null>(null)
  const [fatal, setFatal] = useState<string>(embeddedRelease.error)
  const [fatalContext, setFatalContext] = useState<{ transactionId?: string; at: Date } | null>(
    embeddedRelease.error ? { at: new Date() } : null,
  )
  const [busy, setBusy] = useState(false)
  const [runState, setRunState] = useState<RunState>({})
  const [prepared, setPrepared] = useState<PreparedTransaction | null>(null)
  const [planEngine, setPlanEngine] = useState<PlanExecutor | null>(null)
  const [safeEngine, setSafeEngine] = useState<SafeCeremony | null>(null)
  const [safeIndex, setSafeIndex] = useState(0)
  const [progress, setProgress] = useState<SignatureProgress | null>(null)
  const [safeThreshold, setSafeThreshold] = useState<number | null>(null)
  const [selected, setSelected] = useState<number | null>(null)
  const [storageReady, setStorageReady] = useState(false)
  const [progressVerified, setProgressVerified] = useState(false)
  const [anvilDecisionPending, setAnvilDecisionPending] = useState(false)
  const [rpcUnavailable, setRpcUnavailable] = useState('')
  const [reverifyRun, setReverifyRun] = useState(0)
  const [preparing, setPreparing] = useState(false)
  const [sendPhase, setSendPhase] = useState<'wallet' | 'receipt' | null>(null)
  const [submittedHash, setSubmittedHash] = useState<Hex | null>(null)
  const [railWidth, setRailWidth] = useState(DEFAULT_RAIL_WIDTH)
  const paneRef = useRef<HTMLElement | null>(null)
  const [block, setBlock] = useState<{ number: bigint; ok: boolean } | null>(null)
  const railResize = useRef<{ pointerId: number; startX: number; startWidth: number } | null>(null)
  const embeddedPackage = embeddedRelease.value

  const plan = planArtifact?.value ?? null
  const storageKey = embeddedPackage?.digest ?? planArtifact?.hash ?? null
  const isAnvilPlan = plan?.network === 'anvil' && plan.chainId === 31337
  const chainMismatch = Boolean(isConnected && plan && chainId !== plan.chainId)
  const manifests = useMemo(
    () => manifestArtifacts.map((artifact) => artifact.value),
    [manifestArtifacts],
  )

  function handleError(error: unknown): 'fatal' | 'rpc' | 'notice' {
    const text = errorText(error)
    let storedActionCount = Object.keys(runState).length
    if (planArtifact) {
      try {
        const latest =
          mode === 'eoa'
            ? planEngine?.getRunState()
            : safeEngine?.getRunState()
        const stored =
          latest ??
          new LocalStorageProgressStore(embeddedPackage?.digest ?? planArtifact.hash).load()
        setRunState(stored)
        storedActionCount = Object.keys(stored).length
      } catch {
        // Keep the last React snapshot if the stored evidence itself cannot be decoded.
      }
    }
    if (isRpcUnavailableError(error)) {
      setPrepared(null)
      setPlanEngine(null)
      setSafeEngine(null)
      setProgressVerified(false)
      setAnvilDecisionPending(needsAnvilResumeDecision(isAnvilPlan, storedActionCount))
      setMessage(null)
      setRpcUnavailable(text)
      return 'rpc'
    }
    if (
      error instanceof CeremonyHaltError &&
      (error.fatal ||
        /predicate/i.test(text) ||
        /resume halted|reverted|non-contiguous|nonce mismatch|Safe (?:hash|version) mismatch|transaction service .*?(?:does not match|malformed|unexpected|executed without)|threshold .*does not match|confirmation from non-owner|unexpected Safe/i.test(text))
    ) {
      setFatal(text)
      setFatalContext({ transactionId: error.transactionId, at: new Date() })
      return 'fatal'
    }
    const short = shortErrorText(error)
    setMessage({ tone: 'warn', text: short, detail: short === text ? undefined : text })
    return 'notice'
  }

  useEffect(() => {
    if (__CEREMONY_PACKAGE__ !== null) return
    const parameters = new URLSearchParams(window.location.search)
    const planUrl = parameters.get('plan')
    const manifestUrls = parameters.getAll('manifest')
    const expectedUrl = parameters.get('expectedAddresses')
    if (!planUrl) return
    void (async () => {
      try {
        const loadedPlan = await fetchArtifact<unknown>(planUrl)
        setPlanArtifact({ ...loadedPlan, value: assertPlan(loadedPlan.value) })
        if (manifestUrls.length > 0) {
          const loaded = await Promise.all(
            manifestUrls.map(async (url) => {
              const artifact = await fetchArtifact<unknown>(url)
              return { ...artifact, value: assertManifest(artifact.value) }
            }),
          )
          if (!expectedUrl) throw new Error('Safe URL loading also requires expectedAddresses=<url>.')
          const addresses = await fetchArtifact<unknown>(expectedUrl)
          setManifestArtifacts(loaded)
          setExpectedArtifact({ ...addresses, value: assertExpectedAddresses(addresses.value) })
          setMode('safe')
        }
      } catch (error) {
        handleError(error)
      }
    })()
  }, [])

  useEffect(() => {
    try {
      const saved = Number(window.localStorage.getItem('wildcat-deploy:rail-width'))
      if (Number.isFinite(saved) && saved > 0) {
        setRailWidth(clampRailWidth(saved, window.innerWidth))
      }
    } catch {
      // Resizing still works for this page view when browser storage is unavailable.
    }
  }, [])

  useEffect(() => {
    const constrain = () => {
      setRailWidth((width) => clampRailWidth(width, window.innerWidth))
    }
    window.addEventListener('resize', constrain)
    return () => window.removeEventListener('resize', constrain)
  }, [])

  useEffect(() => {
    setStorageReady(false)
    setProgressVerified(false)
    setAnvilDecisionPending(false)
    setRpcUnavailable('')
    setRunState({})
    if (!storageKey) {
      setStorageReady(true)
      return
    }
    try {
      const stored = new LocalStorageProgressStore(storageKey).load()
      setRunState(stored)
      setAnvilDecisionPending(
        needsAnvilResumeDecision(isAnvilPlan, Object.keys(stored).length),
      )
    } catch (error) {
      setFatal(`Stored run state is invalid: ${errorText(error)}`)
      setFatalContext({ at: new Date() })
    } finally {
      setStorageReady(true)
    }
  }, [isAnvilPlan, storageKey])

  useEffect(() => {
    if (!isConnected) {
      setProgressVerified(false)
      setAnvilDecisionPending(
        needsAnvilResumeDecision(isAnvilPlan, Object.keys(runState).length),
      )
    }
  }, [isAnvilPlan, isConnected, runState])

  useEffect(() => {
    setPrepared(null)
    setPreparing(false)
    setPlanEngine(null)
    setSafeEngine(null)
    setProgress(null)
    if (
      !planArtifact ||
      !storageReady ||
      !address ||
      !isConnected ||
      chainMismatch ||
      fatal ||
      anvilDecisionPending
    ) return
    const store = new LocalStorageProgressStore(embeddedPackage?.digest ?? planArtifact.hash)
    const transport = browserExecutionTransport(address)

    if (mode === 'eoa') {
      const engine = new PlanExecutor(planArtifact.value, transport, store)
      let cancelled = false
      setPlanEngine(engine)
      setPreparing(true)
      void engine
        .prepareNext()
        .then((next) => {
          if (cancelled) return
          setRunState(engine.getRunState())
          setPrepared(next)
          setProgressVerified(true)
          setRpcUnavailable('')
          setMessage((current) => (current?.tone === 'info' ? null : current))
        })
        .catch((error: unknown) => {
          if (!cancelled) handleError(error)
        })
        .finally(() => {
          if (!cancelled) setPreparing(false)
        })
      return () => {
        cancelled = true
      }
    }

    if (!expectedArtifact || manifests.length === 0) return
    void (async () => {
      try {
        // EOA ceremonies never touch the Safe SDKs, so they load only on this path.
        const [{ default: Safe }, { default: SafeApiKit }] = await Promise.all([
          import('@safe-global/protocol-kit'),
          import('@safe-global/api-kit'),
        ])
        const protocolKit = await Safe.init({
          provider: injectedProvider() as never,
          signer: address,
          safeAddress: planArtifact.value.expectedExecutor,
          ...(planArtifact.value.chainId === 31337
            ? { contractNetworks: SAFE_1_4_1_FORK_NETWORKS }
            : {}),
        })
        const serviceUrl = import.meta.env.VITE_SAFE_TX_SERVICE_URL
        const localOnly = planArtifact.value.chainId === 31337 ||
          import.meta.env.VITE_SAFE_LOCAL_ONLY === 'true'
        const apiKit = localOnly
          ? null
          : new SafeApiKit({
              chainId: BigInt(planArtifact.value.chainId),
              ...(serviceUrl ? { txServiceUrl: serviceUrl } : {}),
              ...(import.meta.env.VITE_SAFE_API_KEY
                ? { apiKey: import.meta.env.VITE_SAFE_API_KEY }
                : {}),
            })
        const engine = new SafeCeremony(
          planArtifact.value,
          planArtifact.hash,
          manifests,
          expectedArtifact.value,
          transport,
          protocolKit,
          apiKit,
          store,
        )
        const index = await engine.resume()
        setSafeEngine(engine)
        setSafeIndex(index)
        const current = store.load()
        setRunState(current)
        if (index < manifests.length) setProgress(await engine.getProgress(index))
        setProgressVerified(true)
        setRpcUnavailable('')
      } catch (error) {
        handleError(error)
      }
    })()
  }, [
    address,
    chainMismatch,
    embeddedPackage,
    expectedArtifact,
    fatal,
    isConnected,
    isAnvilPlan,
    manifests,
    mode,
    planArtifact,
    reverifyRun,
    storageReady,
    anvilDecisionPending,
  ])

  useEffect(() => {
    if (!safeEngine || !progress || progress.executed || safeIndex >= manifests.length) return
    const poll = window.setInterval(() => {
      void safeEngine
        .getProgressByHash(safeIndex, progress.safeTxHash)
        .then(async (next) => {
          if (!next) return
          setProgress(next)
          if (next.executed) {
            await safeEngine.syncExecuted(safeIndex, next.safeTxHash)
            const current = safeEngine.getRunState()
            setRunState(current)
            setSelected(null)
            const index = await safeEngine.resume()
            setSafeIndex(index)
            setProgress(index < manifests.length ? await safeEngine.getProgress(index) : null)
            setProgressVerified(true)
          }
        })
        .catch(handleError)
    }, 5_000)
    return () => window.clearInterval(poll)
  }, [manifests.length, progress, runState, safeEngine, safeIndex])

  useEffect(() => {
    setSelected(null)
    setSafeThreshold(null)
  }, [mode, planArtifact])

  useEffect(() => {
    setBlock(null)
    if (!isConnected) return
    let provider: ReturnType<typeof injectedProvider>
    try {
      provider = injectedProvider()
    } catch {
      return
    }
    let cancelled = false
    const poll = async () => {
      try {
        const latest = BigInt((await provider.request({ method: 'eth_blockNumber' })) as string)
        if (!cancelled) setBlock({ number: latest, ok: true })
      } catch {
        if (!cancelled) setBlock((current) => (current ? { ...current, ok: false } : null))
      }
    }
    void poll()
    const timer = window.setInterval(() => void poll(), 4_000)
    return () => {
      cancelled = true
      window.clearInterval(timer)
    }
  }, [chainId, isConnected])

  useEffect(() => {
    if (progress) setSafeThreshold(progress.threshold)
  }, [progress])

  async function loadPlan(file: File): Promise<void> {
    try {
      const artifact = await readFile<unknown>(file)
      setPlanArtifact({ ...artifact, value: assertPlan(artifact.value) })
      setFatal('')
      setMessage(null)
    } catch (error) {
      handleError(error)
    }
  }

  async function loadBundles(files: FileList): Promise<void> {
    try {
      const all = Array.from(files)
      const manifestFiles = all.filter((file) => /bundle-[0-9]+\.manifest\.json$/.test(file.name))
      const expectedFile = all.find((file) => file.name === 'expected-addresses.json')
      if (manifestFiles.length === 0 || !expectedFile) {
        throw new Error('Choose bundle manifests and expected-addresses.json together.')
      }
      const loaded = await Promise.all(
        manifestFiles.map(async (file) => {
          const artifact = await readFile<unknown>(file)
          return { ...artifact, value: assertManifest(artifact.value) }
        }),
      )
      const expected = await readFile<unknown>(expectedFile)
      setManifestArtifacts(loaded)
      setExpectedArtifact({ ...expected, value: assertExpectedAddresses(expected.value) })
      setMode('safe')
      setMessage(null)
    } catch (error) {
      handleError(error)
    }
  }

  function connectWallet(): void {
    if (connectors[0]) connect({ connector: connectors[0] })
  }

  function startNewAnvilRehearsal(): void {
    if (!storageKey || !isAnvilPlan) return
    const confirmed = window.confirm(
      'Start a new Anvil rehearsal? This removes only this package\'s browser run state. Export it first if it is evidence you need to keep.',
    )
    if (!confirmed) return
    new LocalStorageProgressStore(storageKey).clear()
    window.location.reload()
  }

  function resumeAnvilRehearsal(): void {
    setRpcUnavailable('')
    setMessage({
      tone: 'info',
      text: isConnected
        ? 'Re-verifying stored progress against this Anvil fork…'
        : 'Resume selected. Connect the wallet to re-verify this Anvil fork.',
    })
    setAnvilDecisionPending(false)
    setReverifyRun((value) => value + 1)
  }

  function retryRpcConnection(): void {
    setRpcUnavailable('')
    setMessage({ tone: 'info', text: 'Reconnecting and re-verifying on-chain state…' })
    setReverifyRun((value) => value + 1)
  }

  function persistRailWidth(width: number): void {
    try {
      window.localStorage.setItem('wildcat-deploy:rail-width', String(width))
    } catch {
      // The current page still keeps the selected width.
    }
  }

  function beginRailResize(event: ReactPointerEvent<HTMLDivElement>): void {
    const target = event.currentTarget
    railResize.current = {
      pointerId: event.pointerId,
      startX: event.clientX,
      startWidth: railWidth,
    }
    target.setPointerCapture(event.pointerId)
    event.preventDefault()
  }

  function moveRailResize(event: ReactPointerEvent<HTMLDivElement>): void {
    const drag = railResize.current
    if (!drag || drag.pointerId !== event.pointerId) return
    setRailWidth(clampRailWidth(drag.startWidth + event.clientX - drag.startX, window.innerWidth))
  }

  function endRailResize(event: ReactPointerEvent<HTMLDivElement>): void {
    const drag = railResize.current
    if (!drag || drag.pointerId !== event.pointerId) return
    const width = clampRailWidth(drag.startWidth + event.clientX - drag.startX, window.innerWidth)
    railResize.current = null
    if (event.currentTarget.hasPointerCapture(event.pointerId)) {
      event.currentTarget.releasePointerCapture(event.pointerId)
    }
    setRailWidth(width)
    persistRailWidth(width)
  }

  function cancelRailResize(event: ReactPointerEvent<HTMLDivElement>): void {
    if (railResize.current?.pointerId !== event.pointerId) return
    railResize.current = null
    if (event.currentTarget.hasPointerCapture(event.pointerId)) {
      event.currentTarget.releasePointerCapture(event.pointerId)
    }
  }

  function resizeRailWithKeyboard(event: ReactKeyboardEvent<HTMLDivElement>): void {
    let next = railWidth
    if (event.key === 'ArrowLeft') next -= 16
    else if (event.key === 'ArrowRight') next += 16
    else if (event.key === 'Home') next = MIN_RAIL_WIDTH
    else if (event.key === 'End') next = MAX_RAIL_WIDTH
    else return
    event.preventDefault()
    const constrained = clampRailWidth(next, window.innerWidth)
    setRailWidth(constrained)
    persistRailWidth(constrained)
  }

  function resetRailWidth(): void {
    const width = clampRailWidth(DEFAULT_RAIL_WIDTH, window.innerWidth)
    setRailWidth(width)
    persistRailWidth(width)
  }

  async function executeEoa(): Promise<void> {
    if (!planEngine || !prepared) return
    setBusy(true)
    setMessage(null)
    setSendPhase('wallet')
    try {
      const result = await planEngine.execute(prepared, (hash) => {
        setSubmittedHash(hash)
        setSendPhase('receipt')
      })
      setRunState(result.runState)
      setMessage({
        tone: 'ok',
        text: `Transaction ${prepared.index + 1} verified`,
        code: prepared.transaction.id,
        detail: result.predicateDetail,
      })
      setSelected(null)
      setSendPhase(null)
      setPrepared(null)
      setPreparing(true)
      setPrepared(await planEngine.prepareNext())
    } catch (error) {
      if (handleError(error) === 'notice') {
        // Never re-arm a transaction that failed; re-verify and prepare it again.
        setPrepared(null)
        setReverifyRun((value) => value + 1)
      }
    } finally {
      setBusy(false)
      setPreparing(false)
      setSendPhase(null)
      setSubmittedHash(null)
    }
  }

  async function safeAction(action: 'propose' | 'sign' | 'execute'): Promise<void> {
    if (!safeEngine) return
    setBusy(true)
    setMessage(null)
    try {
      if (action === 'sign') {
        setProgress(await safeEngine.sign(safeIndex))
        setMessage({ tone: 'ok', text: `Bundle ${safeIndex + 1} signed.` })
        return
      }
      const result = action === 'propose'
        ? await safeEngine.propose(safeIndex)
        : await safeEngine.execute(safeIndex)
      setProgress(result.progress)
      setRunState(result.runState)
      setMessage({
        tone: 'ok',
        text: result.direct
          ? `Bundle ${safeIndex + 1} executed directly and all predicates passed.`
          : action === 'propose'
            ? `Bundle ${safeIndex + 1} proposed with the connected owner's signature.`
            : `Bundle ${safeIndex + 1} executed and all predicates passed.`,
      })
      if (result.progress.executed) {
        setSelected(null)
        const next = await safeEngine.resume()
        setSafeIndex(next)
        setProgress(next < manifests.length ? await safeEngine.getProgress(next) : null)
      }
    } catch (error) {
      handleError(error)
    } finally {
      setBusy(false)
    }
  }

  const displayedRunState = runStateForDisplay(runState, progressVerified)

  function exportRunState(): void {
    if (plan) saveJson(`run-state-${plan.release}.json`, runState)
  }

  const outputs = useMemo(() => {
    if (!plan) return new Map<string, Address>()
    if (mode === 'safe' && expectedArtifact) {
      return new Map(Object.entries(expectedArtifact.value)) as Map<string, Address>
    }
    const resolved = new Map<string, Address>()
    for (const transaction of plan.transactions) {
      if (transaction.kind !== 'deploy') continue
      const entryAddress = displayedRunState[transaction.id]?.resolvedAddress
      if (entryAddress) resolved.set(transaction.output, entryAddress)
    }
    return resolved
  }, [displayedRunState, expectedArtifact, mode, plan])

  const xrefs = useMemo(
    () => (plan ? buildKeccakXrefs(plan) : { blobHash: new Map(), hashUse: new Map() }),
    [plan],
  )
  const groups = useMemo(() => (plan ? groupPlan(plan) : []), [plan])
  const reverifyClosers = useMemo(() => {
    const closers = new Map<string, number>()
    plan?.transactions.forEach((transaction, index) => {
      if (transaction.reverifyUntil) closers.set(transaction.reverifyUntil, index)
    })
    return closers
  }, [plan])

  const totalSteps = plan?.transactions.length ?? 0
  const verifiedCount = plan
    ? plan.transactions.filter(
        (transaction) => displayedRunState[transaction.id]?.status === 'verified',
      ).length
    : 0
  const firstUnverified = plan
    ? plan.transactions.findIndex(
        (transaction) => displayedRunState[transaction.id]?.status !== 'verified',
      )
    : -1
  const storedVerifiedCount = Object.values(runState).filter(
    (entry) => entry.status === 'verified',
  ).length
  const eoaActiveIndex = prepared?.index ?? (firstUnverified === -1 ? totalSteps : firstUnverified)
  const eoaComplete =
    progressVerified &&
    plan !== null &&
    firstUnverified === -1 &&
    Object.keys(displayedRunState).length > 0
  const completedBundles = manifests.filter((manifest) =>
    manifest.innerTransactions.every(
      (entry) => displayedRunState[entry.planId]?.status === 'verified',
    ),
  ).length
  const safeComplete = progressVerified && manifests.length > 0 && safeIndex >= manifests.length
  const callFingerprint = embeddedPackage
    ? embeddedPackage.fingerprint
    : planArtifact
      ? fingerprint(planArtifact.hash)
      : null

  const selectionLimit = mode === 'eoa' ? totalSteps : manifests.length
  const activeSelection = mode === 'eoa' ? Math.min(eoaActiveIndex, totalSteps - 1) : Math.min(safeIndex, manifests.length - 1)
  const displayIndex = selected ?? Math.max(activeSelection, 0)
  const storedProgressCount = Object.keys(runState).length
  const ceremonyComplete = mode === 'eoa' ? eoaComplete : safeComplete
  const reviewingSelection =
    selected !== null &&
    (ceremonyComplete || (activeSelection >= 0 && selected !== activeSelection))
  const executorMatches =
    plan !== null &&
    address !== undefined &&
    address.toLowerCase() === plan.expectedExecutor.toLowerCase()
  const frameStyle = { '--rail-width': `${railWidth}px` } as CSSProperties
  const blockedReason = !plan
    ? null
    : anvilDecisionPending
      ? 'choose “Resume same Anvil fork” or “Start new rehearsal” in the banner above.'
      : !isConnected
        ? null
        : chainMismatch
          ? `the wallet is on chain ${chainId}; switch it to chain ${plan.chainId}.`
          : rpcUnavailable
            ? 'the RPC is unavailable — restore it, then retry from the banner above.'
            : message?.tone === 'warn' && !prepared && !preparing && !busy
              ? 'preparation stopped — see the message above.'
              : null

  useEffect(() => {
    function onKey(event: KeyboardEvent): void {
      if (event.metaKey || event.ctrlKey || event.altKey) return
      const target = event.target as HTMLElement | null
      if (target && ['INPUT', 'TEXTAREA', 'SELECT'].includes(target.tagName)) return
      if (selectionLimit === 0) return
      if (event.key === 'j') setSelected(Math.min(displayIndex + 1, selectionLimit - 1))
      else if (event.key === 'k') setSelected(Math.max(displayIndex - 1, 0))
      else if (event.key === 'Enter' && !(target && target.tagName === 'BUTTON')) setSelected(null)
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [displayIndex, selectionLimit])

  useEffect(() => {
    paneRef.current?.scrollTo({ top: 0 })
  }, [displayIndex, ceremonyComplete])

  if (fatal) {
    const opener = plan?.transactions.find((transaction) => transaction.reverifyUntil)
    const compensation = opener
      ? plan?.transactions.find((transaction) => transaction.id === opener.reverifyUntil)
      : undefined
    const compensationPending = Boolean(
      opener &&
        runState[opener.id]?.txHash &&
        compensation &&
        runState[compensation.id]?.status !== 'verified',
    )
    return (
      <CeremonyHaltScreen
        message={fatal}
        plan={plan}
        mode={mode}
        callFingerprint={callFingerprint}
        runState={runState}
        compensationId={compensationPending ? compensation?.id : undefined}
        haltedId={fatalContext?.transactionId}
        digest={embeddedPackage?.digest ?? planArtifact?.hash}
        at={fatalContext?.at}
      />
    )
  }

  const railFooter = plan ? (
    <>
      <span className="rail-rule">Any failed check halts. Resume rechecks completed actions.</span>
      <br />
      {mode === 'eoa' ? 'expected EOA' : 'expected Safe'}{' '}
      <AddressValue value={plan.expectedExecutor} />
      <br />
      {planArtifact?.name ?? 'plan'} · hash{' '}
      <code title={planArtifact?.hash}>{short(planArtifact?.hash ?? '')}</code>
      {embeddedPackage ? (
        <>
          <br />
          ceremony digest <code title={embeddedPackage.digest}>{short(embeddedPackage.digest)}</code>
        </>
      ) : null}
      {expectedArtifact ? (
        <>
          <br />
          expected-addresses hash{' '}
          <code title={expectedArtifact.hash}>{short(expectedArtifact.hash)}</code>
        </>
      ) : null}
    </>
  ) : null

  const railGroups: RailGroupModel[] =
    plan === null
      ? []
      : mode === 'eoa'
        ? groups.map((group) => ({
            title: group.title,
            rows: plan.transactions
              .slice(group.start, group.start + group.count)
              .map((transaction, offset) => {
                const index = group.start + offset
                const status = displayedRunState[transaction.id]?.status
                return {
                  key: transaction.id,
                  number: index + 1,
                  label: stepLabel(transaction.id, transaction.description),
                  title: transaction.id,
                  status:
                    status === 'verified'
                      ? 'done'
                      : status === 'reverted' || status === 'predicate-failed'
                        ? 'fail'
                        : index === eoaActiveIndex && !eoaComplete
                          ? 'now'
                          : 'todo',
                  selectIndex: index,
                } satisfies RailRowModel
              }),
          }))
        : manifests.map((manifest, bundleIndex) => ({
            title: `Bundle ${manifest.bundle.number} · nonce ${manifest.bundle.safeNonce}`,
            detail: bundleIndex === safeIndex && !safeComplete ? '· current' : undefined,
            rows: manifest.innerTransactions.map((entry) => {
              const status = displayedRunState[entry.planId]?.status
              return {
                key: entry.planId,
                number: entry.planIndex + 1,
                label: stepLabel(entry.planId, entry.description),
                title: entry.planId,
                status: status === 'verified' ? 'done' : 'todo',
                selectIndex: bundleIndex,
              } satisfies RailRowModel
            }),
          }))

  return (
    <div className="app">
      <header className="bar">
        <span className="brand">
          WILDCAT <em>DEPLOY CEREMONY</em>
        </span>
        {plan ? (
          <>
            <span className="chip">
              {plan.release} <span className="lt">· {plan.network} {plan.chainId}</span>
            </span>
            <ExecutionIdentity
              mode={mode}
              actionCount={totalSteps}
              bundleCount={manifests.length}
              expectedExecutor={plan.expectedExecutor}
              safeVersion={manifests[0]?.safe.version}
            />
          </>
        ) : null}
        {callFingerprint ? (
          <span
            className="chip fp"
            title="Everyone on the call reads this aloud before signing — it must match on every screen. The colors come from the same digest."
          >
            FP {callFingerprint}
            {embeddedPackage?.digest ?? planArtifact?.hash ? (
              <FingerprintBand digest={embeddedPackage?.digest ?? planArtifact?.hash ?? ''} />
            ) : null}
          </span>
        ) : null}
        <span className="spacer"></span>
        {plan && !embeddedPackage ? (
          <span className="devmode" role="group" aria-label="Executor mode (dev builds only)">
            <button className={mode === 'eoa' ? 'on' : ''} onClick={() => setMode('eoa')}>
              EOA
            </button>
            <button className={mode === 'safe' ? 'on' : ''} onClick={() => setMode('safe')}>
              Safe
            </button>
          </span>
        ) : null}
        <div className="bar-session">
          {isConnected && address ? (
            <span
              className="wallet"
              title={
                mode === 'eoa' && plan
                  ? executorMatches
                    ? 'Connected wallet matches the plan’s expected executor'
                    : 'Connected wallet is NOT the plan’s expected executor'
                  : safeEngine
                    ? 'Connected signer is a verified owner of the expected Safe'
                    : 'Connected signer ownership has not been verified'
              }
            >
              <span
                className={`dot${
                  (mode === 'eoa' && plan && !executorMatches) || (mode === 'safe' && !safeEngine)
                    ? ' off'
                    : ''
                }`}
              ></span>
              {mode === 'safe' ? (safeEngine ? 'owner ' : 'signer ') : 'executor '}
              {short(address)}
              {mode === 'eoa' && executorMatches
                ? ' ✓'
                : mode === 'safe'
                  ? safeEngine
                    ? ' ✓'
                    : ' · owner unverified'
                  : ''}
              <button onClick={() => disconnect()}>disconnect</button>
            </span>
          ) : (
            <button
              className="ghost"
              onClick={connectWallet}
              disabled={connecting || connectors.length === 0}
            >
              {connecting ? 'Connecting…' : 'Connect wallet'}
            </button>
          )}
          <button
            className="ghost"
            onClick={exportRunState}
            disabled={!plan || Object.keys(runState).length === 0}
          >
            Export run state
          </button>
        </div>
      </header>

      {plan ? (
        <div className={`ceremony-guidance${embeddedPackage ? '' : ' dev'}`} role="note">
          <strong>{embeddedPackage ? 'Reviewed package.' : 'Development mode.'}</strong>{' '}
          {embeddedPackage
            ? 'Confirm the fingerprint before signing. '
            : 'Loaded artifacts are not locked. '}
          Any failed on-chain check halts the ceremony; resuming rechecks completed actions.
        </div>
      ) : null}

      {plan && storageReady && storedProgressCount > 0 && !progressVerified ? (
        <div className="stored-progress" role="alert">
          <div>
            <strong>Stored progress is not verified against the connected chain.</strong>{' '}
            This browser has {storedProgressCount} saved action
            {storedProgressCount === 1 ? '' : 's'} for this exact package.
            {isAnvilPlan
              ? anvilDecisionPending
                ? ' Choose whether this is the same Anvil process or a fresh fork before continuing.'
                : ' Resume is selected; connect the wallet and wait for every saved receipt and predicate to be checked.'
              : ' Connect the expected signer and wait for receipt and predicate verification before continuing.'}
          </div>
          {isAnvilPlan && anvilDecisionPending ? (
            <div className="stored-actions">
              <button className="ghost" onClick={resumeAnvilRehearsal}>
                Resume same Anvil fork
              </button>
              <button className="danger-ghost" onClick={startNewAnvilRehearsal}>
                Start new rehearsal
              </button>
            </div>
          ) : null}
        </div>
      ) : null}

      {plan && rpcUnavailable ? (
        <div className="rpc-unavailable" role="alert">
          <div>
            <strong>{isAnvilPlan ? 'Local Anvil RPC is unavailable.' : 'Wallet RPC is unavailable.'}</strong>{' '}
            Stop signing. Do not resend a submitted transaction. Restore the endpoint, then re-verify
            stored progress before continuing.
          </div>
          {!isAnvilPlan || storedProgressCount === 0 ? (
            <button className="ghost" onClick={retryRpcConnection}>
              Retry RPC
            </button>
          ) : null}
          <details>
            <summary>RPC error details</summary>
            <pre>{rpcUnavailable}</pre>
          </details>
        </div>
      ) : null}

      {!planArtifact ? (
        <div className="loader-wrap">
          <div className="loader">
            <h2>Load ceremony artifacts</h2>
            <p>
              Development and debugging only — release builds embed the reviewed package and lock
              the mode. EOA testnet runs need the deployment plan; a Safe ceremony also needs the
              bundle output directory (<code>bundle-N.manifest.json</code> +{' '}
              <code>expected-addresses.json</code>).
            </p>
            {message ? <p role="status">{message.text}</p> : null}
            <div>
              <label htmlFor="plan-file">Deployment plan</label>
              <input
                id="plan-file"
                type="file"
                accept="application/json,.json"
                onChange={(event) => event.target.files?.[0] && void loadPlan(event.target.files[0])}
              />
            </div>
            <div>
              <label htmlFor="bundle-files">Safe bundle directory</label>
              <input
                id="bundle-files"
                type="file"
                accept="application/json,.json"
                multiple
                {...({ webkitdirectory: '' } as Record<string, string>)}
                onChange={(event) => event.target.files && void loadBundles(event.target.files)}
              />
            </div>
          </div>
        </div>
      ) : (
        <div className="frame" style={frameStyle}>
          <Rail
            groups={railGroups}
            selectedIndex={ceremonyComplete && selected === null ? -1 : displayIndex}
            onSelect={(index) => setSelected(index)}
            head={
              plan ? (
                <>
                  <div className="rail-head-line">
                    <CeremonyProgress
                      mode={mode}
                      activeEoaIndex={eoaActiveIndex}
                      actionCount={totalSteps}
                      verifiedActions={verifiedCount}
                      bundleCount={manifests.length}
                      completedBundles={completedBundles}
                      signatureProgress={progress}
                      safeThreshold={safeThreshold}
                    />
                    {block ? <BlockHeartbeat block={block} /> : null}
                  </div>
                  <ProgressSegments
                    groups={railGroups}
                    activeGroup={mode === 'safe' && !safeComplete ? safeIndex : -1}
                    complete={ceremonyComplete}
                  />
                </>
              ) : null
            }
            footer={railFooter}
          />
          <div
            className="rail-resizer"
            role="separator"
            aria-label="Resize ceremony steps panel"
            aria-orientation="vertical"
            aria-valuemin={MIN_RAIL_WIDTH}
            aria-valuemax={MAX_RAIL_WIDTH}
            aria-valuenow={railWidth}
            tabIndex={0}
            title="Drag to resize · double-click to reset"
            onPointerDown={beginRailResize}
            onPointerMove={moveRailResize}
            onPointerUp={endRailResize}
            onPointerCancel={cancelRailResize}
            onKeyDown={resizeRailWithKeyboard}
            onDoubleClick={resetRailWidth}
          />
          <section className="pane" ref={paneRef}>
            {reviewingSelection ? (
              <div className="review-notice" role="status">
                Reviewing {mode === 'eoa' ? 'transaction' : 'bundle'} {displayIndex + 1};{' '}
                {ceremonyComplete
                  ? 'the ceremony is complete.'
                  : `the ceremony is waiting at ${mode === 'eoa' ? 'transaction' : 'bundle'} ${activeSelection + 1}.`}
                <button className="mini" onClick={() => setSelected(null)}>
                  {ceremonyComplete ? 'Back to summary' : 'Return to current'}
                </button>
              </div>
            ) : null}
            {message && !(message.tone === 'ok' && reviewingSelection) ? (
              <div
                className={`notice ${message.tone}`}
                role="status"
                key={`${message.tone}:${message.text}:${message.code ?? ''}`}
              >
                {message.tone === 'ok' ? <strong>✓ {message.text}</strong> : message.text}
                {message.code ? (
                  <>
                    {' '}
                    <code>{message.code}</code>
                  </>
                ) : null}
                {message.detail && message.tone === 'warn' ? (
                  <details>
                    <summary>details</summary>
                    <pre>{message.detail}</pre>
                  </details>
                ) : message.detail ? (
                  <span className="notice-detail">{message.detail}</span>
                ) : null}
              </div>
            ) : null}
            {chainMismatch && plan && (
              <div className="chain-error" role="alert">
                Wrong network. This plan requires chain {plan.chainId}; the wallet is on chain{' '}
                {chainId}. No transaction can be sent.
              </div>
            )}
            {mode === 'eoa' ? (
              plan && (selected === null && eoaComplete ? (
                <div className="pane-in">
                  <div className="crumb">ceremony complete</div>
                  <h2 className="ptitle">All {totalSteps} plan predicates are green.</h2>
                  <div className="state-strip done">
                    ✓ COMPLETE{' '}
                    <span className="sans">
                      {eoaCompletionGuidance(plan.release, plan.network)}
                    </span>
                  </div>
                  <div className="complete-actions">
                    <button className="primary" onClick={exportRunState}>
                      Export run-state-{plan.release}.json
                    </button>
                  </div>
                  <CompletionReceipt plan={plan} runState={displayedRunState} />
                </div>
              ) : (
                <EoaStepPane
                  plan={plan}
                  index={Math.min(displayIndex, totalSteps - 1)}
                  groups={groups}
                  runState={displayedRunState}
                  prepared={prepared}
                  activeIndex={eoaActiveIndex}
                  outputs={outputs}
                  xrefs={xrefs}
                  reverifyClosers={reverifyClosers}
                  isConnected={isConnected}
                  busy={busy}
                  chainMismatch={chainMismatch}
                  blocked={blockedReason}
                  sendPhase={sendPhase}
                  submittedHash={submittedHash}
                  connecting={connecting}
                  reverifyCount={storedVerifiedCount}
                  onConnect={connectWallet}
                  onExecute={() => void executeEoa()}
                />
              ))
            ) : manifests.length === 0 ? (
              <div className="pane-in">
                <div className="crumb">safe ceremony</div>
                <h2 className="ptitle">Load bundle manifests to begin.</h2>
                <p className="plain" style={{ marginTop: '12px' }}>
                  Safe mode needs every <code>bundle-N.manifest.json</code> plus{' '}
                  <code>expected-addresses.json</code>. Use the loader on a fresh page, or the URL
                  parameters described in the README.
                </p>
              </div>
            ) : selected === null && safeComplete ? (
              <div className="pane-in">
                <div className="crumb">ceremony complete</div>
                <h2 className="ptitle">All bundle predicates are green.</h2>
                <div className="state-strip done">
                  ✓ COMPLETE{' '}
                  <span className="sans">
                    export the run state and hand it unchanged to step 08.
                  </span>
                </div>
                {plan ? (
                  <>
                    <div className="complete-actions">
                      <button className="primary" onClick={exportRunState}>
                        Export run-state-{plan.release}.json
                      </button>
                    </div>
                    <CompletionReceipt plan={plan} runState={displayedRunState} />
                  </>
                ) : null}
              </div>
            ) : (
              <SafeBundlePane
                manifest={manifests[Math.min(displayIndex, manifests.length - 1)]}
                manifestArtifact={manifestArtifacts[Math.min(displayIndex, manifests.length - 1)]}
                bundleIndex={Math.min(displayIndex, manifests.length - 1)}
                bundleCount={manifests.length}
                isActive={Math.min(displayIndex, manifests.length - 1) === safeIndex && !safeComplete}
                runState={displayedRunState}
                progress={progress}
                outputs={outputs}
                busy={busy}
                chainMismatch={chainMismatch}
                engineReady={safeEngine !== null}
                isConnected={isConnected}
                connecting={connecting}
                onConnect={connectWallet}
                onAction={(action) => void safeAction(action)}
              />
            )}
          </section>
        </div>
      )}
    </div>
  )
}

function EoaStepPane({
  plan,
  index,
  groups,
  runState,
  prepared,
  activeIndex,
  outputs,
  xrefs,
  reverifyClosers,
  isConnected,
  busy,
  chainMismatch,
  blocked,
  sendPhase,
  submittedHash,
  connecting,
  reverifyCount,
  onConnect,
  onExecute,
}: {
  plan: DeploymentPlan
  index: number
  groups: RailGroup[]
  runState: RunState
  prepared: PreparedTransaction | null
  activeIndex: number
  outputs: Map<string, Address>
  xrefs: KeccakXrefs
  reverifyClosers: Map<string, number>
  isConnected: boolean
  busy: boolean
  chainMismatch: boolean
  blocked: string | null
  sendPhase: 'wallet' | 'receipt' | null
  submittedHash: Hex | null
  connecting: boolean
  reverifyCount: number
  onConnect: () => void
  onExecute: () => void
}) {
  const transaction = plan.transactions[index]
  const [title, subtitle] = descriptionParts(transaction.description, transaction.id)
  const entry = runState[transaction.id]
  const verified = entry?.status === 'verified'
  const isActive = index === activeIndex
  const group = groups.find((candidate) => index >= candidate.start && index < candidate.start + candidate.count)
  const total = plan.transactions.length
  const reverifyTargetIndex = transaction.reverifyUntil
    ? plan.transactions.findIndex((candidate) => candidate.id === transaction.reverifyUntil)
    : -1
  const closesIndex = reverifyClosers.get(transaction.id)
  const activeNote =
    sendPhase === 'wallet'
      ? 'waiting for approval in your wallet — nothing has been sent yet.'
      : sendPhase === 'receipt'
        ? `submitted ${submittedHash ? short(submittedHash) : ''} — waiting for the receipt and the on-chain check.`
        : prepared && !busy
          ? 'this is the transaction your wallet will sign — review before sending.'
          : isConnected
            ? reverifyCount > 0
              ? `re-verifying ${reverifyCount} completed check${reverifyCount === 1 ? '' : 's'} and preparing this transaction…`
              : 'preparing this transaction…'
            : 'connect a wallet to prepare this transaction.'

  return (
    <>
      <div className="pane-in">
        <div className="crumb">
          transaction {String(index + 1).padStart(2, '0')} / {total}
          {group ? (
            <>
              {' · '}
              <b>{group.title}</b>
            </>
          ) : null}
        </div>
        <h2 className="ptitle">{title}</h2>
        {subtitle ? <p className="psub">{subtitle}</p> : null}
        <StateStrip
          entry={entry}
          isActive={isActive}
          activeNote={activeNote}
          blocked={isActive ? blocked : null}
          queuedBehind={index > activeIndex ? index - activeIndex : null}
        />
        {reverifyTargetIndex >= 0 ? (
          <div className="operator-note">
            Temporary ownership remains an open checkpoint until transaction{' '}
            {reverifyTargetIndex + 1} returns it.
          </div>
        ) : closesIndex !== undefined ? (
          <div className="operator-note">
            This transaction closes the temporary ownership window opened at transaction{' '}
            {closesIndex + 1}.
          </div>
        ) : null}
        <div className="sect">
          <div className="sect-h">expected result</div>
          <p className="plain">
            {plainPredicateResult(transaction.predicate)}{' '}
            {verified
              ? 'The on-chain check has passed.'
              : 'The page checks this automatically after the transaction mines.'}
          </p>
        </div>
        <details className="tech">
          <summary>technical details</summary>
          <div className="tech-in">
            <div className="sect">
              <div className="sect-h">transaction</div>
              <div className="facts">
                <span className="k">plan id</span>
                <span className="v">
                  <code>{transaction.id}</code>
                </span>
                <span className="k">action</span>
                <span className="v">
                  {transaction.kind === 'deploy' ? (
                    <>
                      deploy <code>{contractName(transaction.artifactName)}</code>{' '}
                      <span className="dim">({transaction.artifactName.split(':')[0]})</span>
                    </>
                  ) : (
                    <>
                      {transaction.forwardedCall ? 'forward ' : 'call '}
                      <code>
                        {transaction.forwardedCall?.functionSignature ?? transaction.functionSignature}
                      </code>
                    </>
                  )}
                </span>
                <span className="k">{transaction.kind === 'deploy' ? 'output' : 'target'}</span>
                <span className="v">
                  {transaction.kind === 'deploy' ? (
                    <RefValue reference={transaction.output} outputs={outputs} />
                  ) : (
                    <TargetValue
                      target={transaction.forwardedCall?.target ?? transaction.to}
                      outputs={outputs}
                    />
                  )}
                </span>
                {transaction.kind === 'call' && transaction.forwardedCall ? (
                  <>
                    <span className="k">via helper</span>
                    <span className="v">
                      <TargetValue target={transaction.to} outputs={outputs} /> ·{' '}
                      <code>{transaction.functionSignature}</code>
                    </span>
                  </>
                ) : null}
                <span className="k">value</span>
                <span className="v">
                  <code>{transactionValueLabel(transaction.envelope.value)}</code>
                  {transaction.envelope.value !== '0' ? (
                    <span className="dim"> · {transaction.envelope.value} wei</span>
                  ) : null}
                </span>
                <span className="k">gas policy</span>
                <span className="v">
                  <code>
                    {transaction.envelope.gasLimitPolicy === 'estimate*1.3'
                      ? 'estimate × 1.3'
                      : `explicit ${numberFormat.format(Number(transaction.envelope.gasLimitPolicy.gasLimit))}`}
                  </code>
                </span>
                {transaction.kind === 'deploy' ? (
                  <>
                    <span className="k">initCode</span>
                    <span className="v">
                      <BytesValue value={transaction.initCode} xrefs={xrefs} stepIndex={index} />
                    </span>
                  </>
                ) : (
                  <>
                    <span className="k">calldata</span>
                    <span className="v">
                      {transaction.calldata.length > 66 ? (
                        <BytesValue value={transaction.calldata} />
                      ) : (
                        <>
                          <code title={transaction.calldata}>{transaction.calldata}</code>
                          <CopyButton value={transaction.calldata} />
                        </>
                      )}
                    </span>
                  </>
                )}
                {isActive && prepared ? (
                  <>
                    <span className="k">nonce / gas</span>
                    <span className="v">
                      <code>{prepared.nonce}</code> · est{' '}
                      <code>{prepared.estimatedGas.toLocaleString('en-US')}</code> · limit{' '}
                      <code>{prepared.gasLimit.toLocaleString('en-US')}</code>
                    </span>
                  </>
                ) : null}
                {entry ? (
                  <>
                    <span className="k">result</span>
                    <span className="v">
                      tx <code title={entry.txHash}>{short(entry.txHash)}</code>
                      <CopyButton value={entry.txHash} />
                      {entry.blockNumber !== undefined
                        ? ` · block ${numberFormat.format(Number(entry.blockNumber))}`
                        : ''}
                      {entry.resolvedAddress ? (
                        <>
                          {' · '}
                          <AddressValue value={entry.resolvedAddress} />
                        </>
                      ) : null}
                    </span>
                  </>
                ) : null}
              </div>
            </div>
            <div className="sect">
              <div className="sect-h">arguments</div>
              <ArgsTable transaction={transaction} stepIndex={index} outputs={outputs} xrefs={xrefs} />
            </div>
            <div className="sect">
              <div className="sect-h">on-chain check</div>
              <div className="checkbox-blk">
                <CheckAssertion predicate={transaction.predicate} outputs={outputs} verified={verified} />
                <div className={`checknote${verified ? ' ok' : ''}`}>
                  {verified
                    ? '✓ verified — the ceremony halts if this ever reads differently.'
                    : 'Runs automatically after the transaction mines. A mismatch halts the ceremony.'}
                </div>
              </div>
            </div>
          </div>
        </details>
      </div>
      {isActive && !verified ? (
        <div className="actionbar">
          {!isConnected && !blocked ? (
            <button className="primary" onClick={onConnect} disabled={connecting}>
              {connecting ? 'Connecting…' : 'Connect wallet'}
            </button>
          ) : (
            <button
              className="primary"
              onClick={onExecute}
              disabled={busy || chainMismatch || blocked !== null || !prepared}
            >
              {sendPhase === 'wallet'
                ? 'Confirm in wallet…'
                : sendPhase === 'receipt'
                  ? 'Waiting for receipt…'
                  : blocked || (prepared && !busy)
                    ? `Send transaction ${index + 1} of ${total}`
                    : 'Preparing…'}
            </button>
          )}
          <span className="sub">
            {blocked
              ? 'blocked — see the status above'
              : !isConnected
                ? `connect the expected executor ${short(plan.expectedExecutor)}`
                : sendPhase === 'wallet'
                  ? 'nothing has been sent yet'
                  : sendPhase === 'receipt'
                    ? 'submitted — keep this page open until the check passes'
                    : prepared && !busy
                      ? `your wallet will open — it should show ${transactionValueLabel(transaction.envelope.value)} being sent`
                      : ''}
          </span>
        </div>
      ) : null}
    </>
  )
}

function SafeBundlePane({
  manifest,
  manifestArtifact,
  bundleIndex,
  bundleCount,
  isActive,
  runState,
  progress,
  outputs,
  busy,
  chainMismatch,
  engineReady,
  isConnected,
  connecting,
  onConnect,
  onAction,
}: {
  manifest: BundleManifest
  manifestArtifact: HashedArtifact<BundleManifest> | undefined
  bundleIndex: number
  bundleCount: number
  isActive: boolean
  runState: RunState
  progress: SignatureProgress | null
  outputs: Map<string, Address>
  busy: boolean
  chainMismatch: boolean
  engineReady: boolean
  isConnected: boolean
  connecting: boolean
  onConnect: () => void
  onAction: (action: 'propose' | 'sign' | 'execute') => void
}) {
  const complete = manifest.innerTransactions.every(
    (entry) => runState[entry.planId]?.status === 'verified',
  )
  const bundleProgress = isActive ? progress : null
  const firstPlanId = manifest.innerTransactions[0]?.planId
  const executedEntry = firstPlanId ? runState[firstPlanId] : undefined

  return (
    <>
      <div className="pane-in">
        <div className="crumb">
          bundle {bundleIndex + 1} / {bundleCount} · <b>Safe <code>{short(manifest.safe.address)}</code></b>
        </div>
        <h2 className="ptitle">
          Bundle {manifest.bundle.number}: {manifest.innerTransactions.length} reviewed
          transactions, executed atomically.
        </h2>
        {complete ? (
          <div className="state-strip done">
            ✓ VERIFIED{' '}
            <span className="sans">
              every action in this bundle passed its on-chain check
              {executedEntry ? (
                <>
                  {' · tx '}
                  <code title={executedEntry.txHash}>{short(executedEntry.txHash)}</code>
                </>
              ) : null}
              .
            </span>
          </div>
        ) : isActive ? (
          <div className="state-strip now">
            ▶ CURRENT{' '}
            <span className="sans">
              {bundleProgress
                ? bundleProgress.confirmations >= bundleProgress.threshold
                  ? 'signature threshold met — ready to execute.'
                  : `${bundleProgress.confirmations} of ${bundleProgress.threshold} signatures collected.`
                : engineReady
                  ? 'loading signature progress…'
                  : 'connect an owner wallet to propose, sign, or execute.'}
            </span>
          </div>
        ) : (
          <div className="state-strip">
            ○ QUEUED{' '}
            <span className="sans">bundles execute strictly in order. Shown for review only.</span>
          </div>
        )}
        <div className="sect">
          <div className="sect-h">what this bundle does</div>
          <p className="plain">
            It executes {manifest.innerTransactions.length} reviewed actions as one atomic Safe
            transaction — either every action succeeds, or none of them happen. The Safe requires{' '}
            {bundleProgress ? bundleProgress.threshold : 'its configured number of'} owner
            signatures before it can run, at Safe nonce {manifest.bundle.safeNonce}.
          </p>
          <div className="safehash">
            <span className="sh-label">compare before you approve</span>
            <div className="sh-value">
              <HexChunks value={manifest.safeTransaction.safeTxHash} />
              <CopyButton value={manifest.safeTransaction.safeTxHash} />
            </div>
            <div className="checknote">
              Your wallet (or the Safe app) must show exactly this Safe transaction hash. If it
              shows anything else, do not sign.
            </div>
          </div>
        </div>
        <div className="sect">
          <div className="sect-h">actions in this bundle</div>
          <ol className="inner-list">
            {manifest.innerTransactions.map((entry) => (
              <li key={entry.planId}>
                <span className="in">{String(entry.planIndex + 1).padStart(2, '0')}</span>
                <span className="id-desc">
                  {plainDescription(entry.description, entry.planId)}
                </span>
                <StatusPill status={runState[entry.planId]?.status} />
              </li>
            ))}
          </ol>
        </div>
        <div className="sect">
          <div className="sect-h">expected result</div>
          <p className="plain">
            Every action above must pass its reviewed on-chain check after the bundle executes.
            {complete ? ' All checks have passed.' : ' The page runs those checks automatically.'}
          </p>
        </div>
        <details className="tech">
          <summary>technical details</summary>
          <div className="tech-in">
            <div className="sect">
              <div className="sect-h">safe transaction</div>
              <div className="facts">
                <span className="k">Safe</span>
                <span className="v">
                  <AddressValue value={manifest.safe.address} /> · <code>v{manifest.safe.version}</code>
                </span>
                <span className="k">to</span>
                <span className="v">
                  <AddressValue value={manifest.safeTransaction.to} />{' '}
                  <span className="dim">(MultiSend)</span>
                </span>
                <span className="k">operation</span>
                <span className="v">
                  <code>1 · delegatecall</code>
                </span>
                <span className="k">value</span>
                <span className="v">
                  <code>{transactionValueLabel(manifest.safeTransaction.value)}</code>
                  {manifest.safeTransaction.value !== '0' ? (
                    <span className="dim"> · {manifest.safeTransaction.value} wei</span>
                  ) : null}
                </span>
                <span className="k">safe nonce</span>
                <span className="v">
                  <code>{manifest.bundle.safeNonce}</code>
                </span>
                <span className="k">safeTxHash</span>
                <span className="v">
                  <HexChunks value={manifest.safeTransaction.safeTxHash} />
                  <CopyButton value={manifest.safeTransaction.safeTxHash} />
                </span>
                <span className="k">gas</span>
                <span className="v">
                  static <code>{manifest.bundle.staticGasEstimate}</code> · simulated{' '}
                  <code>{manifest.bundle.simulatedGas ?? 'not recorded'}</code> · ceiling{' '}
                  <code>{manifest.bundle.maxGas}</code>
                </span>
                {manifestArtifact ? (
                  <>
                    <span className="k">manifest hash</span>
                    <span className="v">
                      <code title={manifestArtifact.hash}>{short(manifestArtifact.hash)}</code>
                      <CopyButton value={manifestArtifact.hash} />
                    </span>
                  </>
                ) : null}
              </div>
            </div>
            <div className="sect">
              <div className="sect-h">per-action checks</div>
              {manifest.innerTransactions.map((entry) => (
                <div className="safe-action-detail" key={entry.planId}>
                  <div className="safe-action-title">
                    {String(entry.planIndex + 1).padStart(2, '0')} · {entry.description}
                  </div>
                  <div className="facts safe-action-facts">
                    <span className="k">kind / target</span>
                    <span className="v">
                      {entry.kind} · <AddressValue value={entry.logicalTarget} />
                    </span>
                    {entry.precomputedAddress ? (
                      <>
                        <span className="k">precomputed</span>
                        <span className="v">
                          <AddressValue value={entry.precomputedAddress} />
                        </span>
                      </>
                    ) : null}
                    <span className="k">gas</span>
                    <span className="v">
                      static <code>{entry.staticGasEstimate}</code> · simulated{' '}
                      <code>{entry.simulatedGas ?? 'not recorded'}</code>
                    </span>
                  </div>
                  <CheckAssertion
                    predicate={entry.predicate}
                    outputs={outputs}
                    verified={runState[entry.planId]?.status === 'verified'}
                  />
                </div>
              ))}
            </div>
          </div>
        </details>
      </div>
      {isActive && !complete && !isConnected ? (
        <div className="actionbar">
          <button className="primary" onClick={onConnect} disabled={connecting}>
            {connecting ? 'Connecting…' : 'Connect wallet'}
          </button>
          <span className="sub">connect a Safe owner wallet</span>
        </div>
      ) : isActive && !complete ? (
        <div className="actionbar">
          <button
            className="primary"
            onClick={() => onAction('propose')}
            disabled={busy || chainMismatch || !engineReady || (bundleProgress?.confirmations ?? 0) > 0}
          >
            Propose &amp; sign
          </button>
          <button
            className="ghost"
            onClick={() => onAction('sign')}
            disabled={
              busy ||
              chainMismatch ||
              !engineReady ||
              !bundleProgress ||
              bundleProgress.confirmations === 0 ||
              bundleProgress.confirmations >= bundleProgress.threshold
            }
          >
            Sign
          </button>
          <button
            className="ghost"
            onClick={() => onAction('execute')}
            disabled={
              busy ||
              chainMismatch ||
              !engineReady ||
              !bundleProgress ||
              bundleProgress.confirmations < bundleProgress.threshold
            }
          >
            Execute
          </button>
          <span className="sub">
            signatures {bundleProgress?.confirmations ?? 0} of {bundleProgress?.threshold ?? '…'}
          </span>
        </div>
      ) : null}
    </>
  )
}

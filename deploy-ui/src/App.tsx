import { useEffect, useMemo, useState, type ReactNode } from 'react'
import Safe from '@safe-global/protocol-kit'
import SafeApiKit from '@safe-global/api-kit'
import { useAccount, useConnect, useDisconnect } from 'wagmi'
import { keccak256 } from 'viem'
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

type Mode = 'eoa' | 'safe'

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

function friendlyLabel(description: string): string {
  return description
    .replace(' the v2.5 ', ' ')
    .replace(' for this deployment', '')
    .replace(/\.$/, '')
}

function functionName(signature: string): string {
  return signature.split('(')[0]
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
  return transaction.kind === 'deploy' ? transaction.constructorArgs.decoded : transaction.args
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
    if (transaction.id.startsWith('remove-')) return 'Retire superseded'
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

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error)
}

function CopyButton({ value }: { value: string }) {
  const [copied, setCopied] = useState(false)
  return (
    <button
      className="copy"
      title="Copy full value"
      onClick={() => {
        void navigator.clipboard?.writeText(value)
        setCopied(true)
        window.setTimeout(() => setCopied(false), 900)
      }}
    >
      {copied ? '✓' : '⧉'}
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
      : parseSignatureTypes(transaction.functionSignature, values.length)
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
      <span className="assert">
        code present at <TargetValue target={predicate.target} outputs={outputs} />
        {mark}
      </span>
    )
  }
  const args = predicate.call.args.map((value) => inlineValue(value, outputs)).join(', ')
  return (
    <span className="assert">
      <TargetValue target={predicate.target} outputs={outputs} /> . {functionName(predicate.call.sig)}
      ({args})<span className="eq">==</span>
      {isReference(predicate.expect) ? (
        <RefValue reference={predicate.expect.$ref} outputs={outputs} />
      ) : typeof predicate.expect === 'string' && isAddressString(predicate.expect) ? (
        <AddressValue value={predicate.expect} />
      ) : (
        <code>{JSON.stringify(predicate.expect)}</code>
      )}
      {mark}
    </span>
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
  footer,
}: {
  groups: RailGroupModel[]
  selectedIndex: number
  onSelect: (index: number) => void
  footer: ReactNode
}) {
  return (
    <nav className="rail" aria-label="Ceremony steps">
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
      </div>
      <div className="fineprint">{footer}</div>
    </nav>
  )
}

function StateStrip({
  entry,
  isActive,
  isConnected,
  ready,
  queuedBehind,
}: {
  entry: RunStateEntry | undefined
  isActive: boolean
  isConnected: boolean
  ready: boolean
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
  if (isActive) {
    return (
      <div className="state-strip now">
        ▶ UP NEXT{' '}
        <span className="sans">
          {ready
            ? 'this is the transaction your wallet will sign — review before sending.'
            : isConnected
              ? 'preparing the transaction…'
              : 'connect a wallet to prepare this transaction.'}
        </span>
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
  const [message, setMessage] = useState<string>('')
  const [fatal, setFatal] = useState<string>(embeddedRelease.error)
  const [busy, setBusy] = useState(false)
  const [runState, setRunState] = useState<RunState>({})
  const [prepared, setPrepared] = useState<PreparedTransaction | null>(null)
  const [planEngine, setPlanEngine] = useState<PlanExecutor | null>(null)
  const [safeEngine, setSafeEngine] = useState<SafeCeremony | null>(null)
  const [safeIndex, setSafeIndex] = useState(0)
  const [progress, setProgress] = useState<SignatureProgress | null>(null)
  const [selected, setSelected] = useState<number | null>(null)
  const embeddedPackage = embeddedRelease.value

  const plan = planArtifact?.value ?? null
  const chainMismatch = Boolean(isConnected && plan && chainId !== plan.chainId)
  const manifests = useMemo(
    () => manifestArtifacts.map((artifact) => artifact.value),
    [manifestArtifacts],
  )

  function handleError(error: unknown): void {
    const text = errorMessage(error)
    if (
      error instanceof CeremonyHaltError &&
      (/predicate/i.test(text) ||
        /resume halted|reverted|non-contiguous|nonce mismatch|Safe (?:hash|version) mismatch|transaction service .*?(?:does not match|malformed|unexpected|executed without)|threshold .*does not match|confirmation from non-owner|unexpected Safe/i.test(text))
    ) {
      setFatal(text)
    } else {
      setMessage(text)
    }
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
    setPrepared(null)
    setPlanEngine(null)
    setSafeEngine(null)
    setProgress(null)
    if (!planArtifact || !address || !isConnected || chainMismatch || fatal) return
    const store = new LocalStorageProgressStore(embeddedPackage?.digest ?? planArtifact.hash)
    const transport = browserExecutionTransport(address)

    if (mode === 'eoa') {
      const engine = new PlanExecutor(planArtifact.value, transport, store)
      setPlanEngine(engine)
      void engine
        .prepareNext()
        .then((next) => {
          setRunState(engine.getRunState())
          setPrepared(next)
        })
        .catch(handleError)
      return
    }

    if (!expectedArtifact || manifests.length === 0) return
    void (async () => {
      try {
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
        setRunState(store.load())
        if (index < manifests.length) setProgress(await engine.getProgress(index))
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
    manifests,
    mode,
    planArtifact,
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
            setRunState(safeEngine.getRunState())
            const index = await safeEngine.resume()
            setSafeIndex(index)
            setProgress(index < manifests.length ? await safeEngine.getProgress(index) : null)
          }
        })
        .catch(handleError)
    }, 5_000)
    return () => window.clearInterval(poll)
  }, [manifests.length, progress, runState, safeEngine, safeIndex])

  // Surface locally stored progress before a wallet connects; engines replace it once live.
  useEffect(() => {
    if (!planArtifact || planEngine || safeEngine) return
    try {
      setRunState(new LocalStorageProgressStore(embeddedPackage?.digest ?? planArtifact.hash).load())
    } catch {
      /* corrupted local progress surfaces as a halt once an engine loads */
    }
  }, [embeddedPackage, planArtifact, planEngine, safeEngine])

  useEffect(() => {
    setSelected(null)
  }, [mode, planArtifact])

  async function loadPlan(file: File): Promise<void> {
    try {
      const artifact = await readFile<unknown>(file)
      setPlanArtifact({ ...artifact, value: assertPlan(artifact.value) })
      setFatal('')
      setMessage('')
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
      setMessage('')
    } catch (error) {
      handleError(error)
    }
  }

  async function executeEoa(): Promise<void> {
    if (!planEngine || !prepared) return
    setBusy(true)
    setMessage('')
    try {
      const result = await planEngine.execute(prepared)
      setRunState(result.runState)
      setMessage(`${prepared.transaction.id}: ${result.predicateDetail}`)
      setPrepared(await planEngine.prepareNext())
    } catch (error) {
      handleError(error)
    } finally {
      setBusy(false)
    }
  }

  async function safeAction(action: 'propose' | 'sign' | 'execute'): Promise<void> {
    if (!safeEngine) return
    setBusy(true)
    setMessage('')
    try {
      if (action === 'sign') {
        setProgress(await safeEngine.sign(safeIndex))
        setMessage(`Bundle ${safeIndex + 1} signed.`)
        return
      }
      const result = action === 'propose'
        ? await safeEngine.propose(safeIndex)
        : await safeEngine.execute(safeIndex)
      setProgress(result.progress)
      setRunState(result.runState)
      setMessage(
        result.direct
          ? `Bundle ${safeIndex + 1} executed directly and all predicates passed.`
          : action === 'propose'
            ? `Bundle ${safeIndex + 1} proposed with the connected owner's signature.`
            : `Bundle ${safeIndex + 1} executed and all predicates passed.`,
      )
      if (result.progress.executed) {
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

  const outputs = useMemo(() => {
    if (!plan) return new Map<string, Address>()
    if (mode === 'safe' && expectedArtifact) {
      return new Map(Object.entries(expectedArtifact.value)) as Map<string, Address>
    }
    const resolved = new Map<string, Address>()
    for (const transaction of plan.transactions) {
      if (transaction.kind !== 'deploy') continue
      const entryAddress = runState[transaction.id]?.resolvedAddress
      if (entryAddress) resolved.set(transaction.output, entryAddress)
    }
    return resolved
  }, [expectedArtifact, mode, plan, runState])

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
    ? plan.transactions.filter((transaction) => runState[transaction.id]?.status === 'verified').length
    : 0
  const firstUnverified = plan
    ? plan.transactions.findIndex((transaction) => runState[transaction.id]?.status !== 'verified')
    : -1
  const eoaActiveIndex = prepared?.index ?? (firstUnverified === -1 ? totalSteps : firstUnverified)
  const eoaComplete = plan !== null && firstUnverified === -1 && Object.keys(runState).length > 0
  const safeComplete = manifests.length > 0 && safeIndex >= manifests.length
  const callFingerprint = embeddedPackage
    ? embeddedPackage.fingerprint
    : planArtifact
      ? fingerprint(planArtifact.hash)
      : null

  const selectionLimit = mode === 'eoa' ? totalSteps : manifests.length
  const activeSelection = mode === 'eoa' ? Math.min(eoaActiveIndex, totalSteps - 1) : Math.min(safeIndex, manifests.length - 1)
  const displayIndex = selected ?? Math.max(activeSelection, 0)

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

  if (fatal) {
    const compensation = plan?.transactions.find((transaction) =>
      plan.transactions.some((candidate) => candidate.reverifyUntil === transaction.id),
    )
    const compensationPending = compensation && runState[compensation.id]?.status !== 'verified'
    return (
      <main className="fatal-screen">
        <p className="eyebrow">CEREMONY HALTED</p>
        <h1>Do not continue.</h1>
        <pre>{fatal}</pre>
        <p>Preserve the loaded files and run state. There is intentionally no skip button.</p>
        {compensationPending && (
          <p>
            Temporary ownership may still be held by the deployment EOA. Before ending the
            session, use the reviewed recovery procedure to execute{' '}
            <code>{compensation.id}</code> and confirm its predicate.
          </p>
        )}
      </main>
    )
  }

  const railFooter = plan ? (
    <>
      on failure: halt — resume re-verifies all prior predicates
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
                const status = runState[transaction.id]?.status
                return {
                  key: transaction.id,
                  number: index + 1,
                  label: friendlyLabel(transaction.description),
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
              const status = runState[entry.planId]?.status
              return {
                key: entry.planId,
                number: entry.planIndex + 1,
                label: friendlyLabel(entry.description),
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
            <span className="chip">{plan.release}</span>
            <span className="chip">
              {plan.network} <span className="lt">· {plan.chainId}</span>
            </span>
          </>
        ) : null}
        {callFingerprint ? (
          <span
            className="chip fp"
            title="Everyone on the call reads this aloud before signing — it must match on every screen"
          >
            FP {callFingerprint}
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
        {plan ? (
          <span className="meter">
            <b>{verifiedCount}</b>/{totalSteps}
            <span className="track">
              <i style={{ width: `${totalSteps ? (verifiedCount / totalSteps) * 100 : 0}%` }}></i>
            </span>
          </span>
        ) : null}
        {isConnected && address ? (
          <span
            className="wallet"
            title={
              mode === 'eoa' && plan
                ? address.toLowerCase() === plan.expectedExecutor.toLowerCase()
                  ? 'Connected wallet matches the plan’s expected executor'
                  : 'Connected wallet is NOT the plan’s expected executor'
                : 'Connected wallet'
            }
          >
            <span
              className={`dot${
                mode === 'eoa' && plan && address.toLowerCase() !== plan.expectedExecutor.toLowerCase()
                  ? ' off'
                  : ''
              }`}
            ></span>
            {short(address)}
            {mode === 'eoa' && plan && address.toLowerCase() === plan.expectedExecutor.toLowerCase()
              ? ' ✓'
              : ''}
            <button onClick={() => disconnect()}>disconnect</button>
          </span>
        ) : (
          <button
            className="ghost"
            onClick={() => connectors[0] && connect({ connector: connectors[0] })}
            disabled={connecting || connectors.length === 0}
          >
            {connecting ? 'Connecting…' : 'Connect wallet'}
          </button>
        )}
        <button
          className="ghost"
          onClick={() => plan && saveJson(`run-state-${plan.release}.json`, runState)}
          disabled={!plan || Object.keys(runState).length === 0}
        >
          Export run state
        </button>
      </header>

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
            {message ? <p role="status">{message}</p> : null}
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
        <div className="frame">
          <Rail
            groups={railGroups}
            selectedIndex={displayIndex}
            onSelect={(index) => setSelected(index)}
            footer={railFooter}
          />
          <section className="pane">
            {message && (
              <div className="notice" role="status">
                {message}
              </div>
            )}
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
                      export the run state from the top bar and hand it unchanged to step 08.
                    </span>
                  </div>
                </div>
              ) : (
                <EoaStepPane
                  plan={plan}
                  index={Math.min(displayIndex, totalSteps - 1)}
                  groups={groups}
                  runState={runState}
                  prepared={prepared}
                  activeIndex={eoaActiveIndex}
                  outputs={outputs}
                  xrefs={xrefs}
                  reverifyClosers={reverifyClosers}
                  callFingerprint={callFingerprint}
                  isConnected={isConnected}
                  busy={busy}
                  chainMismatch={chainMismatch}
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
                    export the run state from the top bar and hand it unchanged to step 08.
                  </span>
                </div>
              </div>
            ) : (
              <SafeBundlePane
                manifest={manifests[Math.min(displayIndex, manifests.length - 1)]}
                manifestArtifact={manifestArtifacts[Math.min(displayIndex, manifests.length - 1)]}
                bundleIndex={Math.min(displayIndex, manifests.length - 1)}
                bundleCount={manifests.length}
                isActive={Math.min(displayIndex, manifests.length - 1) === safeIndex && !safeComplete}
                runState={runState}
                progress={progress}
                outputs={outputs}
                callFingerprint={callFingerprint}
                busy={busy}
                chainMismatch={chainMismatch}
                engineReady={safeEngine !== null}
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
  callFingerprint,
  isConnected,
  busy,
  chainMismatch,
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
  callFingerprint: string | null
  isConnected: boolean
  busy: boolean
  chainMismatch: boolean
  onExecute: () => void
}) {
  const transaction = plan.transactions[index]
  const entry = runState[transaction.id]
  const verified = entry?.status === 'verified'
  const isActive = index === activeIndex
  const group = groups.find((candidate) => index >= candidate.start && index < candidate.start + candidate.count)
  const total = plan.transactions.length
  const reverifyTargetIndex = transaction.reverifyUntil
    ? plan.transactions.findIndex((candidate) => candidate.id === transaction.reverifyUntil)
    : -1
  const closesIndex = reverifyClosers.get(transaction.id)

  return (
    <>
      <div className="pane-in">
        <div className="crumb">
          step {String(index + 1).padStart(2, '0')} / {total}
          {group ? (
            <>
              {' · '}
              <b>{group.title}</b>
            </>
          ) : null}
        </div>
        <h2 className="ptitle">{transaction.description}</h2>
        <StateStrip
          entry={entry}
          isActive={isActive}
          isConnected={isConnected}
          ready={prepared !== null}
          queuedBehind={index > activeIndex ? index - activeIndex : null}
        />
        <div className="sect">
          <div className="sect-h">what this step does</div>
          <p className="plain">
            {transaction.kind === 'deploy' ? (
              <>
                It creates one new contract on {plan.network} — <b>{contractName(transaction.artifactName)}</b>{' '}
                — and records its address as “{transaction.output.replace(/-/g, ' ')}” so later
                steps can refer to it.
              </>
            ) : (
              <>
                It sends a single instruction, <b>{functionName(transaction.functionSignature)}</b>, to{' '}
                {isReference(transaction.to) ? (
                  <>the new {transaction.to.$ref.replace(/-/g, ' ')}</>
                ) : (
                  <>
                    the contract at <code title={transaction.to}>{short(transaction.to)}</code>
                  </>
                )}
                .
              </>
            )}
            {reverifyTargetIndex >= 0 ? (
              <> Its check stays enforced until step {reverifyTargetIndex + 1} completes.</>
            ) : null}
            {closesIndex !== undefined ? (
              <> Closes the window opened in step {closesIndex + 1}.</>
            ) : null}
          </p>
          {isActive && !verified && callFingerprint ? (
            <p className="plain">
              Everything on this page was compiled from the reviewed release plan — nothing can be
              edited or improvised here. Before sending, confirm the fingerprint in the top bar (
              <b>{callFingerprint}</b>) reads the same on every screen on the call.
            </p>
          ) : null}
        </div>
        <div className="sect">
          <div className="sect-h">automatic safety check</div>
          <p className="plain">
            After the transaction mines, the page immediately re-checks the result on-chain
            {verified ? ' — this check has already passed' : ''}. If a check ever fails, the
            ceremony <b>halts on the spot</b>: no further transaction can be sent, and there is
            deliberately no skip button.
          </p>
          <CheckAssertion predicate={transaction.predicate} outputs={outputs} verified={verified} />
        </div>
        <details className="tech">
          <summary>technical detail</summary>
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
                      call <code>{transaction.functionSignature}</code>
                    </>
                  )}
                </span>
                <span className="k">{transaction.kind === 'deploy' ? 'output' : 'target'}</span>
                <span className="v">
                  {transaction.kind === 'deploy' ? (
                    <RefValue reference={transaction.output} outputs={outputs} />
                  ) : (
                    <TargetValue target={transaction.to} outputs={outputs} />
                  )}
                </span>
                <span className="k">value</span>
                <span className="v">
                  <code>
                    {transaction.envelope.value === '0'
                      ? '0 ETH'
                      : `${transaction.envelope.value} wei`}
                  </code>
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
      {isActive && prepared ? (
        <div className="actionbar">
          <button className="primary" onClick={onExecute} disabled={busy || chainMismatch}>
            {busy ? 'Waiting for receipt…' : `Send transaction ${index + 1} of ${total}`}
          </button>
          <span className="sub">
            {busy
              ? 'transaction submitted — waiting for the receipt and the on-chain check'
              : 'your wallet will open — it should show 0 ETH being sent'}
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
  callFingerprint,
  busy,
  chainMismatch,
  engineReady,
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
  callFingerprint: string | null
  busy: boolean
  chainMismatch: boolean
  engineReady: boolean
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
          bundle {bundleIndex + 1} / {bundleCount} · <b>Safe {short(manifest.safe.address)}</b>
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
          {isActive && !complete && callFingerprint ? (
            <p className="plain">
              Everything here was compiled from the reviewed release plan — nothing can be edited or
              improvised. Before signing, confirm the fingerprint in the top bar (
              <b>{callFingerprint}</b>) reads the same on every screen on the call.
            </p>
          ) : null}
          <div className="safehash">
            <span className="sh-label">compare before you approve</span>
            <code>{manifest.safeTransaction.safeTxHash}</code>
            <CopyButton value={manifest.safeTransaction.safeTxHash} />
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
                  {entry.description}
                  <span className="id-sub">
                    {entry.kind} · <code title={entry.logicalTarget}>{short(entry.logicalTarget)}</code>
                    {entry.precomputedAddress ? (
                      <>
                        {' · precomputed '}
                        <code title={entry.precomputedAddress}>{short(entry.precomputedAddress)}</code>
                      </>
                    ) : null}
                  </span>
                </span>
                <StatusPill status={runState[entry.planId]?.status} />
              </li>
            ))}
          </ol>
        </div>
        <div className="sect">
          <div className="sect-h">automatic safety check</div>
          <p className="plain">
            After execution, the page verifies every action’s on-chain check
            {complete ? ' — all of them have passed' : ''}. If any check fails, the ceremony{' '}
            <b>halts on the spot</b>; there is deliberately no skip button.
          </p>
        </div>
        <details className="tech">
          <summary>technical detail</summary>
          <div className="tech-in">
            <div className="sect">
              <div className="sect-h">safe transaction</div>
              <div className="facts">
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
                  <code>
                    {manifest.safeTransaction.value === '0'
                      ? '0 ETH'
                      : `${manifest.safeTransaction.value} wei`}
                  </code>
                </span>
                <span className="k">safe nonce</span>
                <span className="v">
                  <code>{manifest.bundle.safeNonce}</code>
                </span>
                <span className="k">safeTxHash</span>
                <span className="v">
                  <code title={manifest.safeTransaction.safeTxHash}>
                    {manifest.safeTransaction.safeTxHash}
                  </code>
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
                <div key={entry.planId} style={{ marginBottom: '6px' }}>
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
      {isActive && !complete ? (
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

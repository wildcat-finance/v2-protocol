import { useEffect, useMemo, useState } from 'react'
import Safe from '@safe-global/protocol-kit'
import SafeApiKit from '@safe-global/api-kit'
import { useAccount, useConnect, useDisconnect } from 'wagmi'
import type { Address, Hex } from 'viem'
import {
  assertCeremonyPackage,
  assertExpectedAddresses,
  assertManifest,
  assertPlan,
  fetchArtifact,
  readFile,
  type HashedArtifact,
  type LoadedCeremonyPackage,
} from './artifacts'
import { CeremonyHaltError, PlanExecutor, type PreparedTransaction } from './engine/planExecutor'
import { LocalStorageProgressStore, type RunState } from './engine/runState'
import { SafeCeremony, type SignatureProgress } from './engine/safeCeremony'
import type {
  BundleManifest,
  DeploymentPlan,
  ExpectedAddresses,
  PlanValue,
} from './engine/types'
import { browserExecutionTransport, injectedProvider } from './walletTransport'
import { SAFE_1_4_1_FORK_NETWORKS } from './safeContracts'
import './App.css'

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

function short(value: string): string {
  return value.length > 18 ? `${value.slice(0, 10)}…${value.slice(-6)}` : value
}

function display(value: PlanValue | PlanValue[] | undefined): string {
  if (value === undefined) return '—'
  return JSON.stringify(value, null, 2)
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

function StatusPill({ status }: { status?: string }) {
  return <span className={`pill ${status || 'waiting'}`}>{status || 'waiting'}</span>
}

function HashLine({ label, artifact }: { label: string; artifact: HashedArtifact<unknown> }) {
  return (
    <div className="hash-line">
      <span>{label}</span>
      <code title={artifact.hash}>{artifact.hash}</code>
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

  return (
    <main className="shell">
      <header className="topbar">
        <div>
          <p className="eyebrow">WILDCAT RELEASE CEREMONY</p>
          <h1>Review. Sign. Verify.</h1>
          <p className="lede">One reviewed artifact, one transaction sequence, no editable calldata.</p>
        </div>
        <div className="wallet-box">
          {isConnected && address ? (
            <>
              <strong>{short(address)}</strong>
              <span>Chain {chainId}</span>
              <button className="secondary" onClick={() => disconnect()}>Disconnect</button>
            </>
          ) : (
            <button
              onClick={() => connectors[0] && connect({ connector: connectors[0] })}
              disabled={connecting || connectors.length === 0}
            >
              {connecting ? 'Connecting…' : 'Connect wallet'}
            </button>
          )}
        </div>
      </header>

      {!embeddedPackage && <section className="loader panel">
        <p className="loader-help">
          <strong>Testnet dev run (EOA):</strong> load only the deployment plan
          (<code>plan-&lt;release&gt;.json</code> from step 07) — the page walks every
          transaction as a card your wallet signs. Bundles do not apply to an EOA.
          <br />
          <strong>Mainnet Safe ceremony:</strong> load the plan <em>and</em> the bundle
          output directory (<code>bundle-N.manifest.json</code> +{' '}
          <code>expected-addresses.json</code> from <code>plan.js bundle</code>) — the
          page switches to Safe mode and shows one card per bundle.
        </p>
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
          <label htmlFor="bundle-files">Safe bundle directory/files</label>
          <input
            id="bundle-files"
            type="file"
            accept="application/json,.json"
            multiple
            {...({ webkitdirectory: '' } as Record<string, string>)}
            onChange={(event) => event.target.files && void loadBundles(event.target.files)}
          />
        </div>
      </section>}

      {message && <div className="notice" role="status">{message}</div>}
      {chainMismatch && plan && (
        <div className="chain-error" role="alert">
          Wrong network. This plan requires chain {plan.chainId}; the wallet is on chain {chainId}.
          No transaction can be sent.
        </div>
      )}

      {planArtifact && (
        <>
          <section className="identity panel">
            <div>
              <p className="eyebrow">LOADED ARTIFACT</p>
              <h2>{planArtifact.value.release}</h2>
              <p>{planArtifact.value.network} · chain {planArtifact.value.chainId} · {planArtifact.value.transactions.length} transactions</p>
              <p>Expected executor: <code>{planArtifact.value.expectedExecutor}</code></p>
            </div>
            <div className="hashes">
              {embeddedPackage && (
                <div className="hash-line package-digest">
                  <span>Call fingerprint</span>
                  <strong>{embeddedPackage.fingerprint}</strong>
                </div>
              )}
              {embeddedPackage && (
                <div className="hash-line">
                  <span>Ceremony digest</span>
                  <code title={embeddedPackage.digest}>{embeddedPackage.digest}</code>
                </div>
              )}
              <HashLine label="Plan file hash" artifact={planArtifact} />
              {manifestArtifacts.map((artifact) => (
                <HashLine key={artifact.name} label={artifact.name} artifact={artifact} />
              ))}
              {expectedArtifact && <HashLine label="expected-addresses.json" artifact={expectedArtifact} />}
            </div>
          </section>

          {!embeddedPackage && <nav className="mode-switch" aria-label="Executor mode">
            <button className={mode === 'eoa' ? 'selected' : ''} onClick={() => setMode('eoa')}>
              EOA testnet
            </button>
            <button className={mode === 'safe' ? 'selected' : ''} onClick={() => setMode('safe')}>
              Safe ceremony
            </button>
          </nav>}

          {mode === 'eoa' ? (
            <section className="sequence">
              <div className="section-heading">
                <div>
                  <p className="eyebrow">EOA MODE</p>
                  <h2>Plan sequence</h2>
                </div>
                <button
                  className="secondary"
                  onClick={() => saveJson(`run-state-${planArtifact.value.release}.json`, runState)}
                  disabled={Object.keys(runState).length === 0}
                >Export run state</button>
              </div>
              {planArtifact.value.transactions.map((transaction, index) => {
                const state = runState[transaction.id]
                const active = prepared?.index === index
                return (
                  <article className={`tx-card ${active ? 'active' : ''}`} key={transaction.id}>
                    <div className="card-number">{index + 1}</div>
                    <div className="card-body">
                      <div className="card-title">
                        <div><h3>{transaction.description}</h3><code>{transaction.id}</code></div>
                        <StatusPill status={state?.status} />
                      </div>
                      <dl>
                        <div><dt>Type</dt><dd>{transaction.kind}</dd></div>
                        <div><dt>Target / artifact</dt><dd><code>{transaction.kind === 'deploy' ? transaction.artifactName : display(transaction.to)}</code></dd></div>
                        <div><dt>Decoded arguments</dt><dd><pre>{display(transaction.kind === 'deploy' ? transaction.constructorArgs.decoded : transaction.args)}</pre></dd></div>
                        <div><dt>Predicate</dt><dd><pre>{display(transaction.predicate as PlanValue)}</pre></dd></div>
                        {active && prepared && <>
                          <div><dt>Pending nonce</dt><dd>{prepared.nonce}</dd></div>
                          <div><dt>Estimated / limit gas</dt><dd>{prepared.estimatedGas.toString()} / {prepared.gasLimit.toString()}</dd></div>
                        </>}
                      </dl>
                      {active && (
                        <button onClick={() => void executeEoa()} disabled={busy || chainMismatch}>
                          {busy ? 'Waiting for receipt…' : `Send transaction ${index + 1}`}
                        </button>
                      )}
                    </div>
                  </article>
                )
              })}
              {!prepared && Object.keys(runState).length > 0 && (
                <div className="success-panel">All plan predicates are green. Export the run state for step 08.</div>
              )}
            </section>
          ) : (
            <section className="sequence">
              <div className="section-heading">
                <div>
                  <p className="eyebrow">SAFE MODE · DELEGATECALL</p>
                  <h2>Bundle ceremony</h2>
                </div>
                <button
                  className="secondary"
                  onClick={() => saveJson(`run-state-${planArtifact.value.release}.json`, runState)}
                  disabled={Object.keys(runState).length === 0}
                >Export run state</button>
              </div>
              {manifests.length === 0 && (
                <div className="notice">Load bundle manifests and expected-addresses.json to enter Safe mode.</div>
              )}
              {manifests.map((manifest, index) => {
                const active = index === safeIndex
                const complete = manifest.innerTransactions.every(
                  (entry) => runState[entry.planId]?.status === 'verified',
                )
                return (
                  <article className={`bundle-card ${active ? 'active' : ''}`} key={manifest.bundle.number}>
                    <div className="card-title">
                      <div>
                        <p className="eyebrow">BUNDLE {manifest.bundle.number}</p>
                        <h3>{manifest.innerTransactions.length} reviewed inner transactions</h3>
                      </div>
                      <StatusPill status={complete ? 'verified' : active ? 'current' : undefined} />
                    </div>
                    <p>
                      Safe nonce: <strong>{manifest.bundle.safeNonce}</strong> · simulated gas:{' '}
                      <strong>{manifest.bundle.simulatedGas ?? 'not recorded'}</strong> · ceiling{' '}
                      {manifest.bundle.maxGas}
                    </p>
                    <p>Expected Safe transaction hash: <code>{manifest.safeTransaction.safeTxHash}</code></p>
                    <ol className="inner-list">
                      {manifest.innerTransactions.map((entry) => (
                        <li key={entry.planId}>
                          <div>
                            <strong>{entry.description}</strong>
                            <code>{entry.logicalTarget}</code>
                            {entry.precomputedAddress && <span>Precomputed: <code>{entry.precomputedAddress}</code></span>}
                          </div>
                          <StatusPill status={runState[entry.planId]?.status} />
                        </li>
                      ))}
                    </ol>
                    {active && safeEngine && (
                      <div className="safe-actions">
                        <div className="signature-meter">
                          <span>Signatures</span>
                          <strong>{progress?.confirmations ?? 0} of {progress?.threshold ?? '…'}</strong>
                          {progress?.safeTxHash && <code>{progress.safeTxHash}</code>}
                        </div>
                        <div className="button-row">
                          <button
                            onClick={() => void safeAction('propose')}
                            disabled={busy || chainMismatch || (progress?.confirmations ?? 0) > 0}
                          >
                            Propose &amp; sign
                          </button>
                          <button
                            onClick={() => void safeAction('sign')}
                            disabled={
                              busy ||
                              chainMismatch ||
                              !progress ||
                              progress.confirmations === 0 ||
                              progress.confirmations >= progress.threshold
                            }
                          >
                            Sign
                          </button>
                          <button
                            onClick={() => void safeAction('execute')}
                            disabled={busy || chainMismatch || !progress || progress.confirmations < progress.threshold}
                          >Execute</button>
                        </div>
                      </div>
                    )}
                  </article>
                )
              })}
              {safeIndex === manifests.length && manifests.length > 0 && (
                <div className="success-panel">All bundle predicates are green. Export the run state for step 08.</div>
              )}
            </section>
          )}
        </>
      )}
    </main>
  )
}

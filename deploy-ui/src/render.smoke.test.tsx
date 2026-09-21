// Server-render smoke test for the console UI. Without CEREMONY_PACKAGE it covers the
// dev loader screen; with CEREMONY_PACKAGE=<package.json> (same variable the release build
// uses) it covers the full embedded-plan render: top bar, rail groups, and the step pane.
import { renderToString } from 'react-dom/server'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { WagmiProvider } from 'wagmi'
import { describe, expect, it } from 'vitest'
import miniPlanJson from '../../scripts/__fixtures__/plan/mini-plan.json'
import App, {
  CeremonyHaltScreen,
  CeremonyProgress,
  ExecutionIdentity,
  friendlyLabel,
  transactionValueLabel,
} from './App'
import { assertCeremonyPackage } from './artifacts'
import type { DeploymentPlan } from './engine/types'
import { wagmiConfig } from './wagmi'

const miniPlan = miniPlanJson as DeploymentPlan

function renderApp(): string {
  return renderToString(
    <WagmiProvider config={wagmiConfig}>
      <QueryClientProvider client={new QueryClient()}>
        <App />
      </QueryClientProvider>
    </WagmiProvider>,
  ).replaceAll('<!-- -->', '')
}

describe('App server-render smoke', () => {
  it('presents EOA and Safe execution as first-class ceremony identities', () => {
    const eoa = renderToString(
      <ExecutionIdentity
        mode="eoa"
        actionCount={38}
        bundleCount={0}
        expectedExecutor={miniPlan.expectedExecutor}
      />,
    )
    const safe = renderToString(
      <ExecutionIdentity
        mode="safe"
        actionCount={24}
        bundleCount={3}
        expectedExecutor={miniPlan.expectedExecutor}
        safeVersion="1.4.1"
      />,
    )
    expect(eoa).toContain('EOA')
    expect(eoa).toContain('38 individual transactions')
    expect(safe).toContain('SAFE')
    expect(safe).toContain('3 bundles')
    expect(safe).toContain('24 actions')
    expect(safe).toContain('v1.4.1')
  })

  it('uses mode-specific transaction and Safe-bundle progress', () => {
    const eoa = renderToString(
      <CeremonyProgress
        mode="eoa"
        activeEoaIndex={12}
        actionCount={38}
        verifiedActions={12}
        bundleCount={0}
        completedBundles={0}
        signatureProgress={null}
        safeThreshold={null}
      />,
    ).replaceAll('<!-- -->', '')
    const safe = renderToString(
      <CeremonyProgress
        mode="safe"
        activeEoaIndex={0}
        actionCount={24}
        verifiedActions={8}
        bundleCount={3}
        completedBundles={1}
        signatureProgress={{
          safeTxHash: `0x${'11'.repeat(32)}`,
          confirmations: 2,
          threshold: 3,
          executed: false,
          executionTxHash: null,
        }}
        safeThreshold={3}
      />,
    ).replaceAll('<!-- -->', '')
    expect(eoa).toContain('TX')
    expect(eoa).toContain('<b>13</b>/38')
    expect(eoa).toContain('12/38 checks')
    expect(safe).toContain('BUNDLE')
    expect(safe).toContain('<b>2</b>/3')
    expect(safe).toContain('2/3 signatures')
    expect(safe).toContain('8/24 checks')
  })

  it('keeps evidence export available on a fatal halt', () => {
    const html = renderToString(
      <CeremonyHaltScreen
        message="Predicate mismatch."
        plan={miniPlan}
        mode="eoa"
        callFingerprint="ABCD-1234-EF56"
        runState={{
          [miniPlan.transactions[0].id]: {
            txHash: `0x${'22'.repeat(32)}`,
            status: 'verified',
          },
        }}
        compensationId="restore-ownership"
      />,
    )
    expect(html).toContain('CEREMONY HALTED')
    expect(html).toContain('FP ABCD-1234-EF56')
    expect(html).toContain('Export run state')
    expect(html).toContain('ceremony executor')
    expect(html).not.toContain('Export run state</button><span>No completed')
  })

  it('shortens retirement rows and derives displayed ETH value', () => {
    const address = '0xE3e4B7C9E0Ab4ccbC70e0583Dca7B4Db9B4CFD88'
    expect(
      friendlyLabel(
        `Prevent the superseded hooks factory at ${address} from re-registering as a controller.`,
        'remove-superseded-controller-factory-01',
      ),
    ).toBe('Block factory 0xE3e4B7C9…4CFD88')
    expect(
      friendlyLabel(
        `Prevent the superseded hooks controller at ${address} from registering new markets.`,
        'remove-superseded-controller-01',
      ),
    ).toBe('Block new markets 0xE3e4B7C9…4CFD88')
    expect(transactionValueLabel('0')).toBe('0 ETH')
    expect(transactionValueLabel('1000000000000000000')).toBe('1 ETH')
  })

  if (__CEREMONY_PACKAGE__ === null) {
    it('renders the dev loader when no package is embedded', () => {
      const html = renderApp()
      expect(html).toContain('DEPLOY CEREMONY')
      expect(html).toContain('Load ceremony artifacts')
      expect(html).toContain('Deployment plan')
    })
    return
  }

  it('renders the full console for the embedded plan', () => {
    const embedded = assertCeremonyPackage(__CEREMONY_PACKAGE__)
    const html = renderApp()
    const plainPane = html.split('<section class="pane">')[1]?.split('<details class="tech">')[0] ?? ''
    // top bar identity
    expect(html).toContain('DEPLOY CEREMONY')
    expect(html).toContain(embedded.plan.value.release)
    expect(html).toContain(embedded.plan.value.network)
    expect(html).toContain('FP ')
    expect(html).toContain(embedded.mode === 'eoa' ? 'EOA' : 'SAFE')
    expect((html.match(/class="row /g) ?? []).length).toBe(
      embedded.plan.value.transactions.length,
    )
    if (embedded.mode === 'eoa') {
      // Ceremony stages derived from the real plan.
      expect(html).toContain('Take ownership')
      expect(html).toContain('Deploy contracts')
      expect(html).toContain('Register &amp; wire')
      expect(html).toContain('Retire superseded')
      expect(html).toContain('Return ownership')
      expect(html).toContain('Deploy standard hooks factory')
      expect(html).toContain('Temporarily reclaim ArchController ownership')
      const first = embedded.plan.value.transactions[0]
      if (first.kind === 'call') {
        expect(plainPane).not.toContain(first.functionSignature.split('(')[0])
      }
    } else {
      expect(html).toContain(`${embedded.manifests.length} bundle`)
      expect(html).toContain('executed atomically')
      expect(html).toContain('compare before you approve')
      const firstAddress = embedded.manifests[0].value.innerTransactions[0]?.precomputedAddress
      if (firstAddress) expect(plainPane).not.toContain(firstAddress)
    }
    // Shared pane hierarchy and halt policy.
    expect(html).toContain('expected result')
    expect(html).toContain('technical details')
    const firstPredicate = embedded.plan.value.transactions[0].predicate
    expect(html).toContain(
      firstPredicate.type === 'codePresent'
        ? 'code present at'
        : `${firstPredicate.call.sig.split('(')[0]}()`,
    )
    expect(html).toContain('Any failed on-chain check halts the ceremony')
    // fine print
    expect(html).toContain('Any failed check halts')
    expect(html).toContain('ceremony digest')
  })
})

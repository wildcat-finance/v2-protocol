import { execFileSync } from 'node:child_process'
import { mkdirSync, mkdtempSync, readFileSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join, resolve } from 'node:path'
import { afterAll, beforeAll, describe, expect, it } from 'vitest'
import Safe from '@safe-global/protocol-kit'
import { createWalletClient, getAddress, http, keccak256, stringToHex } from 'viem'
import { privateKeyToAccount } from 'viem/accounts'
import miniPlanJson from '../../../../scripts/__fixtures__/plan/mini-plan.json'
import { MemoryProgressStore } from '../runState'
import { SafeCeremony } from '../safeCeremony'
import type {
  BundleManifest,
  DeploymentPlan,
  ExpectedAddresses,
} from '../types'
import {
  DEV_KEY,
  nodeExecutionTransport,
  startAnvil,
  stopAnvil,
  withCurrentFixtureBytecode,
} from './forkHelpers'
import { SAFE_1_4_1_FORK_NETWORKS } from '../../safeContracts'

const ROOT = resolve(import.meta.dirname, '../../../..')
const MAINNET_RPC_URL =
  process.env.MAINNET_RPC_URL || 'https://ethereum-rpc.publicnode.com'
const SAFE_PROXY_FACTORY_1_4_1 = getAddress(
  '0x4e1DCf7AD4e460CfD30791CCC4F9c8a4f820ec67',
)

describe('SafeCeremony on a live Anvil mainnet fork', () => {
  let anvil: Awaited<ReturnType<typeof startAnvil>>

  beforeAll(async () => {
    anvil = await startAnvil(MAINNET_RPC_URL, 19546)
  }, 90_000)

  afterAll(async () => {
    if (anvil) await stopAnvil(anvil.process)
  })

  it('deploys a fresh canonical 1-of-1 Safe and directly executes one mini-plan bundle', async () => {
    const owner = privateKeyToAccount(DEV_KEY)
    const predicted = await Safe.init({
      provider: anvil.url,
      signer: DEV_KEY,
      predictedSafe: {
        safeAccountConfig: { owners: [owner.address], threshold: 1 },
        safeDeploymentConfig: { safeVersion: '1.4.1' },
      },
      contractNetworks: SAFE_1_4_1_FORK_NETWORKS,
    })
    const safeAddress = getAddress(await predicted.getAddress())
    const deployment = await predicted.createSafeDeploymentTransaction()
    expect(getAddress(deployment.to)).toBe(SAFE_PROXY_FACTORY_1_4_1)
    const walletClient = createWalletClient({ account: owner, transport: http(anvil.url) })
    const deployHash = await walletClient.sendTransaction({
      chain: null,
      to: getAddress(deployment.to),
      data: deployment.data as `0x${string}`,
      value: BigInt(deployment.value),
    })
    const transport = nodeExecutionTransport(anvil.url)
    expect((await transport.waitForReceipt(deployHash)).status).toBe('success')

    const protocolKit = await Safe.init({
      provider: anvil.url,
      signer: DEV_KEY,
      safeAddress,
      contractNetworks: SAFE_1_4_1_FORK_NETWORKS,
    })
    expect(await protocolKit.getContractVersion()).toBe('1.4.1')
    expect(await protocolKit.getThreshold()).toBe(1)

    const plan = withCurrentFixtureBytecode(miniPlanJson as DeploymentPlan, ROOT)
    plan.expectedExecutor = safeAddress
    for (const transaction of plan.transactions) {
      transaction.envelope.expectedExecutor = safeAddress
    }
    const directory = mkdtempSync(join(tmpdir(), 'deploy-ui-safe-'))
    const planPath = join(directory, 'mini-safe-plan.json')
    const bundlesPath = join(directory, 'bundles')
    mkdirSync(bundlesPath)
    const planBytes = `${JSON.stringify(plan, null, 2)}\n`
    writeFileSync(planPath, planBytes)
    const bundleOutput = execFileSync(
      'node',
      [
        'scripts/plan.js',
        'bundle',
        '--plan',
        planPath,
        '--safe',
        safeAddress,
        '--max-gas',
        '20000000',
        '--out-dir',
        bundlesPath,
      ],
      {
        cwd: ROOT,
        encoding: 'utf8',
        env: { ...process.env, FOUNDRY_PROFILE: 'deploy' },
      },
    )
    expect(bundleOutput).toContain('Bundle compilation complete')
    const index = JSON.parse(readFileSync(join(bundlesPath, 'bundle-index.json'), 'utf8'))
    expect(index.bundles).toHaveLength(1)
    const manifests = index.bundles.map((entry: { manifest: string }) =>
      JSON.parse(readFileSync(join(bundlesPath, entry.manifest), 'utf8')) as BundleManifest,
    )
    const expected = JSON.parse(
      readFileSync(join(bundlesPath, 'expected-addresses.json'), 'utf8'),
    ) as ExpectedAddresses
    const planHash = keccak256(stringToHex(planBytes))
    expect(index.planHash).toBe(planHash)

    const store = new MemoryProgressStore()
    const engine = new SafeCeremony(
      plan,
      planHash,
      manifests,
      expected,
      transport,
      protocolKit,
      null,
      store,
    )
    expect(await engine.resume()).toBe(0)
    const result = await engine.propose(0)
    expect(result.direct).toBe(true)
    expect(result.progress.executed).toBe(true)
    expect(result.predicateDetails).toHaveLength(3)
    expect(Object.values(result.runState).every((entry) => entry.status === 'verified')).toBe(true)
    expect(new Set(Object.values(result.runState).map((entry) => entry.txHash)).size).toBe(1)
    expect(await engine.resume()).toBe(1)
  }, 120_000)
})

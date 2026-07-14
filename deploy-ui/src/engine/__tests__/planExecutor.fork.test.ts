import { execFileSync } from 'node:child_process'
import { mkdtempSync, readFileSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join, resolve } from 'node:path'
import { afterAll, beforeAll, describe, expect, it } from 'vitest'
import {
  encodeAbiParameters,
  encodeFunctionData,
  getAddress,
  keccak256,
  pad,
  parseAbi,
} from 'viem'
import miniPlanJson from '../../../../scripts/__fixtures__/plan/mini-plan.json'
import { PlanExecutor } from '../planExecutor'
import { MemoryProgressStore, serializeRunState } from '../runState'
import type { CallTransaction, DeploymentPlan } from '../types'
import {
  nodeExecutionTransport,
  startAnvil,
  stopAnvil,
  withCurrentFixtureBytecode,
} from './forkHelpers'

const ROOT = resolve(import.meta.dirname, '../../../..')
const SEPOLIA_RPC_URL =
  process.env.SEPOLIA_RPC_URL || 'https://ethereum-sepolia-rpc.publicnode.com'
const ARCH_CONTROLLER = getAddress('0xC003f20F2642c76B81e5e1620c6D8cdEE826408f')
const MOCK_OWNER = getAddress('0xa476920af80B587f696734430227869795E2Ea78')
const OWNER_ABI = parseAbi([
  'function returnOwnership()',
  'function transferOwnership(address)',
])

async function rpc(url: string, method: string, params: unknown[]): Promise<unknown> {
  const response = await fetch(url, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ jsonrpc: '2.0', id: 1, method, params }),
  })
  const value = await response.json() as { result?: unknown; error?: { message: string } }
  if (value.error) throw new Error(`${method}: ${value.error.message}`)
  return value.result
}

function withSepoliaOwnership(plan: DeploymentPlan): DeploymentPlan {
  const executor = getAddress(plan.expectedExecutor)
  const envelope = (to: `0x${string}`) => ({
    chainId: plan.chainId,
    expectedExecutor: executor,
    to,
    value: '0',
    data: 'functionSignature+args' as const,
    gasLimitPolicy: 'estimate*1.3' as const,
    nonceCheck: 'display-and-confirm' as const,
  })
  const reclaim: CallTransaction = {
    id: 'reclaim-arch-controller-ownership',
    kind: 'call',
    to: MOCK_OWNER,
    functionSignature: 'returnOwnership()',
    args: [],
    calldata: encodeFunctionData({ abi: OWNER_ABI, functionName: 'returnOwnership' }),
    description: 'Temporarily reclaim ArchController ownership.',
    reverifyUntil: 'restore-arch-controller-ownership',
    envelope: envelope(MOCK_OWNER),
    predicate: {
      type: 'callEq',
      target: ARCH_CONTROLLER,
      call: { sig: 'owner() view returns (address)', args: [] },
      expect: executor,
    },
  }
  const restore: CallTransaction = {
    id: 'restore-arch-controller-ownership',
    kind: 'call',
    to: ARCH_CONTROLLER,
    functionSignature: 'transferOwnership(address)',
    args: [MOCK_OWNER],
    calldata: encodeFunctionData({
      abi: OWNER_ABI,
      functionName: 'transferOwnership',
      args: [MOCK_OWNER],
    }),
    description: 'Return ArchController ownership to the helper.',
    envelope: envelope(ARCH_CONTROLLER),
    predicate: {
      type: 'callEq',
      target: ARCH_CONTROLLER,
      call: { sig: 'owner() view returns (address)', args: [] },
      expect: MOCK_OWNER,
    },
  }
  return { ...plan, transactions: [reclaim, ...plan.transactions, restore] }
}

describe('PlanExecutor on a live Anvil Sepolia fork', () => {
  let anvil: Awaited<ReturnType<typeof startAnvil>>

  beforeAll(async () => {
    anvil = await startAnvil(SEPOLIA_RPC_URL, 19545)
  }, 90_000)

  afterAll(async () => {
    if (anvil) await stopAnvil(anvil.process)
  })

  it('executes the Sepolia reclaim, plan, and restore sequence and produces a plan.js-verifiable run state', async () => {
    const currentPlan = withCurrentFixtureBytecode(miniPlanJson as DeploymentPlan, ROOT)
    const plan = withSepoliaOwnership(currentPlan)
    const authorizedSlot = keccak256(
      encodeAbiParameters(
        [{ type: 'address' }, { type: 'uint256' }],
        [plan.expectedExecutor, 0n],
      ),
    )
    await rpc(anvil.url, 'anvil_setStorageAt', [MOCK_OWNER, authorizedSlot, pad('0x01', { size: 32 })])
    const store = new MemoryProgressStore()
    const engine = new PlanExecutor(plan, nodeExecutionTransport(anvil.url), store)

    let prepared = await engine.prepareNext()
    while (prepared) {
      await engine.execute(prepared)
      if (prepared.transaction.id === 'restore-arch-controller-ownership') {
        const interrupted = store.load()
        interrupted[prepared.transaction.id] = {
          txHash: interrupted[prepared.transaction.id].txHash,
          status: 'submitted',
        }
        store.save(interrupted)
        expect(await new PlanExecutor(
          plan,
          nodeExecutionTransport(anvil.url),
          store,
        ).resume()).toBe(plan.transactions.length)
      }
      prepared = await engine.prepareNext()
    }

    const state = store.load()
    expect(Object.keys(state)).toEqual(plan.transactions.map((transaction) => transaction.id))
    expect(Object.values(state).every((entry) => entry.status === 'verified')).toBe(true)

    const directory = mkdtempSync(join(tmpdir(), 'deploy-ui-eoa-'))
    const statePath = join(directory, 'run-state.json')
    const compatiblePlanPath = join(directory, 'mini-plan-current-bytecode.json')
    writeFileSync(statePath, serializeRunState(state))
    writeFileSync(
      compatiblePlanPath,
      `${JSON.stringify(plan, null, 2)}\n`,
    )
    const output = execFileSync(
      'node',
      [
        'scripts/plan.js',
        'verify',
        '--plan',
        compatiblePlanPath,
        '--run-state',
        statePath,
        '--rpc',
        anvil.url,
      ],
      {
        cwd: ROOT,
        encoding: 'utf8',
        env: { ...process.env, FOUNDRY_PROFILE: 'deploy' },
      },
    )
    expect(output).toContain('Verification passed: 5 predicate(s).')
    expect(readFileSync(statePath, 'utf8')).toBe(serializeRunState(state))
  }, 90_000)
})

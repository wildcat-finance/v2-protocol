import { execFileSync } from 'node:child_process'
import { mkdtempSync, readFileSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join, resolve } from 'node:path'
import { afterAll, beforeAll, describe, expect, it } from 'vitest'
import miniPlanJson from '../../../../scripts/__fixtures__/plan/mini-plan.json'
import { PlanExecutor } from '../planExecutor'
import { MemoryProgressStore, serializeRunState } from '../runState'
import type { DeploymentPlan } from '../types'
import {
  nodeExecutionTransport,
  startAnvil,
  stopAnvil,
  withCurrentFixtureBytecode,
} from './forkHelpers'

const ROOT = resolve(import.meta.dirname, '../../../..')
const SEPOLIA_RPC_URL =
  process.env.SEPOLIA_RPC_URL || 'https://ethereum-sepolia-rpc.publicnode.com'

describe('PlanExecutor on a live Anvil Sepolia fork', () => {
  let anvil: Awaited<ReturnType<typeof startAnvil>>

  beforeAll(async () => {
    anvil = await startAnvil(SEPOLIA_RPC_URL, 19545)
  }, 90_000)

  afterAll(async () => {
    if (anvil) await stopAnvil(anvil.process)
  })

  it('executes mini-plan and produces a plan.js-verifiable run state', async () => {
    const plan = miniPlanJson as DeploymentPlan
    const store = new MemoryProgressStore()
    const engine = new PlanExecutor(plan, nodeExecutionTransport(anvil.url), store)

    let prepared = await engine.prepareNext()
    while (prepared) {
      await engine.execute(prepared)
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
      `${JSON.stringify(withCurrentFixtureBytecode(plan, ROOT), null, 2)}\n`,
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
    expect(output).toContain('Verification passed: 3 predicate(s).')
    expect(readFileSync(statePath, 'utf8')).toBe(serializeRunState(state))
  }, 90_000)
})

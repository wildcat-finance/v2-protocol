import { describe, expect, it } from 'vitest'
import {
  encodeAbiParameters,
  getAddress,
  parseAbiParameters,
  type Address,
  type Hex,
} from 'viem'
import miniPlanJson from '../../../../scripts/__fixtures__/plan/mini-plan.json'
import { evaluatePredicate, resolveReferences } from '../predicates'
import { PlanExecutor } from '../planExecutor'
import {
  MemoryProgressStore,
  outputsFromRunState,
  serializeRunState,
  type RunState,
} from '../runState'
import type {
  DeploymentPlan,
  ExecutionTransport,
  Predicate,
  ReceiptLike,
} from '../types'

const plan = miniPlanJson as DeploymentPlan
const executor = getAddress(plan.expectedExecutor)

class FakeTransport implements ExecutionTransport {
  chainId = plan.chainId
  account = executor
  code = new Map<string, Hex>()
  callResult: Hex = '0x'

  async getChainId() {
    return this.chainId
  }
  async getAccount() {
    return this.account
  }
  async getCode(address: Address) {
    return this.code.get(address.toLowerCase())
  }
  async getTransactionCount() {
    return 7
  }
  async estimateGas() {
    return 100n
  }
  async sendTransaction() {
    return `0x${'12'.repeat(32)}` as Hex
  }
  async waitForReceipt(): Promise<ReceiptLike> {
    return {
      transactionHash: `0x${'12'.repeat(32)}`,
      blockNumber: 9n,
      status: 'success',
      contractAddress: '0x1000000000000000000000000000000000000001',
    }
  }
  async getReceipt() {
    return null
  }
  async ethCall() {
    return this.callResult
  }
}

describe('fixture-driven engine semantics', () => {
  it('resolves nested $refs from the mini plan', () => {
    const address = getAddress('0x1000000000000000000000000000000000000001')
    const decoded = plan.transactions[1].kind === 'deploy'
      ? plan.transactions[1].constructorArgs.decoded
      : []
    expect(resolveReferences(decoded, new Map([['fixture-token', address]]))).toEqual([
      address,
    ])
  })

  it('prepares the first mini-plan transaction and enforces its explicit gas limit', async () => {
    const transport = new FakeTransport()
    const engine = new PlanExecutor(plan, transport, new MemoryProgressStore())
    const prepared = await engine.prepareNext()
    expect(prepared?.transaction.id).toBe('deploy-token')
    expect(prepared?.nonce).toBe(7)
    expect(prepared?.estimatedGas).toBe(100n)
    expect(prepared?.gasLimit).toBe(1_800_000n)
    expect(prepared?.data.startsWith(plan.transactions[0].kind === 'deploy'
      ? plan.transactions[0].initCode
      : 'never')).toBe(true)
  })

  it('evaluates codePresent and callEq exactly like plan.js', async () => {
    const transport = new FakeTransport()
    const target = getAddress('0x1000000000000000000000000000000000000001')
    transport.code.set(target.toLowerCase(), '0x6000')
    expect(
      await evaluatePredicate(
        transport,
        { type: 'codePresent', target },
        new Map(),
      ),
    ).toEqual({ ok: true, detail: `code present at ${target}` })

    transport.callResult = encodeAbiParameters(parseAbiParameters('uint256'), [1000n])
    const predicate: Predicate = {
      type: 'callEq',
      target,
      call: {
        sig: 'balanceOf(address) view returns (uint256)',
        args: [executor],
      },
      expect: '1000',
    }
    expect((await evaluatePredicate(transport, predicate, new Map())).ok).toBe(true)
    expect(
      (await evaluatePredicate(transport, { ...predicate, expect: '999' }, new Map())).detail,
    ).toContain('expected "999", got "1000"')
  })

  it('derives outputs and emits the plan.js run-state shape with a trailing newline', () => {
    const state: RunState = {
      'deploy-token': {
        txHash: `0x${'ab'.repeat(32)}`,
        blockNumber: 123,
        status: 'verified',
        resolvedAddress: '0x1000000000000000000000000000000000000001',
      },
      'mint-token': {
        txHash: `0x${'cd'.repeat(32)}`,
        blockNumber: '9007199254740992',
        status: 'verified',
      },
    }
    expect(outputsFromRunState(plan, state).get('fixture-token')).toBe(
      getAddress('0x1000000000000000000000000000000000000001'),
    )
    expect(serializeRunState(state)).toBe(`${JSON.stringify(state, null, 2)}\n`)
    expect(JSON.parse(serializeRunState(state))).toEqual(state)
  })

  it('halts resume when a verified entry appears after an incomplete entry', async () => {
    const transport = new FakeTransport()
    const state: RunState = {
      'mint-token': {
        txHash: `0x${'cd'.repeat(32)}`,
        blockNumber: 1,
        status: 'verified',
      },
    }
    const engine = new PlanExecutor(plan, transport, new MemoryProgressStore(state))
    await expect(engine.resume()).rejects.toThrow('Run state is non-contiguous')
  })
})

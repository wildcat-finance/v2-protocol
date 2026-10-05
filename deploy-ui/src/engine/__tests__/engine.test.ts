import { describe, expect, it } from 'vitest'
import { createRequire } from 'node:module'
import {
  encodeAbiParameters,
  encodeFunctionData,
  getAddress,
  keccak256,
  parseAbi,
  parseAbiParameters,
  type Address,
  type Hex,
} from 'viem'
import miniPlanJson from '../../../../scripts/__fixtures__/plan/mini-plan.json'
import { buildPlanPayload } from '../planEncoding'
import { evaluatePredicate, resolveReferences } from '../predicates'
import { PlanExecutor, REVERIFY_CONCURRENCY } from '../planExecutor'
import {
  MemoryProgressStore,
  outputsFromRunState,
  serializeRunState,
  type RunState,
} from '../runState'
import type {
  DeploymentPlan,
  DeployTransaction,
  ExecutionTransport,
  ForwardedCallTransaction,
  Predicate,
  ReceiptLike,
} from '../types'

const plan = miniPlanJson as DeploymentPlan
const executor = getAddress(plan.expectedExecutor)
const { checkPredicate: checkCliPredicate, validatePlan } = createRequire(import.meta.url)('../../../../scripts/plan.js')

class FakeTransport implements ExecutionTransport {
  chainId = plan.chainId
  account = executor
  code = new Map<string, Hex>()
  callResult: Hex = '0x'
  waitFailure: Error | null = null
  storedReceipt: ReceiptLike | null = null

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
    if (this.waitFailure) throw this.waitFailure
    return {
      transactionHash: `0x${'12'.repeat(32)}`,
      blockNumber: 9n,
      status: 'success',
      contractAddress: '0x1000000000000000000000000000000000000001',
    }
  }
  async getReceipt() {
    return this.storedReceipt
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

  it('uses reviewed constructor ABI types instead of guessing bytes32 as bytes', () => {
    const domainSeparator = `0x${'ab'.repeat(32)}` as Hex
    const encoded = encodeAbiParameters(parseAbiParameters('address,bytes32'), [
      executor,
      domainSeparator,
    ])
    const transaction: DeployTransaction = {
      id: 'deploy-typed-constructor',
      kind: 'deploy',
      description: 'Deploy a contract with a bytes32 constructor argument.',
      artifactName: 'TypedFixture',
      initCode: '0x60',
      constructorArgs: {
        types: ['address', 'bytes32'],
        decoded: [executor, domainSeparator],
        encoded,
      },
      output: 'typed-fixture',
      envelope: {
        chainId: plan.chainId,
        expectedExecutor: executor,
        to: null,
        value: '0',
        data: 'initCode+constructorArgs',
        gasLimitPolicy: 'estimate*1.3',
        nonceCheck: 'display-and-confirm',
      },
      predicate: { type: 'codePresent', target: { $ref: 'typed-fixture' } },
    }

    expect(buildPlanPayload(transaction, new Map()).data).toBe(
      `0x60${encoded.slice(2)}`,
    )
  })

  it('rebuilds nested helper calldata after resolving the logical target', () => {
    const helper = getAddress('0x2000000000000000000000000000000000000002')
    const factory = getAddress('0x3000000000000000000000000000000000000003')
    const zero = getAddress('0x0000000000000000000000000000000000000000')
    const forwardAbi = parseAbi([
      'function executeProtocolAction(address target, bytes data) returns (bytes result)',
    ])
    const archAbi = parseAbi(['function registerControllerFactory(address factory)'])
    const unresolvedInner = encodeFunctionData({
      abi: archAbi,
      functionName: 'registerControllerFactory',
      args: [zero],
    })
    const transaction: ForwardedCallTransaction = {
      id: 'forward-register-factory',
      kind: 'call',
      description: 'Register the reviewed controller factory through the authority helper.',
      to: helper,
      functionSignature: 'executeProtocolAction(address,bytes)',
      forwardedCall: {
        target: { $ref: 'arch-controller' },
        functionSignature: 'registerControllerFactory(address)',
        args: [{ $ref: 'factory' }],
      },
      calldata: encodeFunctionData({
        abi: forwardAbi,
        functionName: 'executeProtocolAction',
        args: [zero, unresolvedInner],
      }),
      envelope: {
        chainId: plan.chainId,
        expectedExecutor: executor,
        to: helper,
        value: '0',
        data: 'forwardedCall',
        gasLimitPolicy: 'estimate*1.3',
        nonceCheck: 'display-and-confirm',
      },
      predicate: { type: 'codePresent', target: { $ref: 'factory' } },
    }

    const payload = buildPlanPayload(
      transaction,
      new Map([
        ['arch-controller', executor],
        ['factory', factory],
      ]),
    )
    const resolvedInner = encodeFunctionData({
      abi: archAbi,
      functionName: 'registerControllerFactory',
      args: [factory],
    })
    expect(payload).toEqual({
      to: helper,
      data: encodeFunctionData({
        abi: forwardAbi,
        functionName: 'executeProtocolAction',
        args: [executor, resolvedInner],
      }),
      value: 0n,
    })
  })

  it('persists the transaction hash before waiting for a receipt', async () => {
    const transport = new FakeTransport()
    transport.waitFailure = new Error('temporary RPC outage')
    const store = new MemoryProgressStore()
    const engine = new PlanExecutor(plan, transport, store)
    const prepared = await engine.prepareNext()
    if (!prepared) throw new Error('Expected the first transaction to be prepared.')

    await expect(engine.execute(prepared)).rejects.toThrow('Resume instead of resending')
    expect(store.load()['deploy-token']).toEqual({
      txHash: `0x${'12'.repeat(32)}`,
      status: 'submitted',
    })
  })

  it('resumes a submitted deployment from its receipt without resending', async () => {
    const txHash = `0x${'12'.repeat(32)}` as Hex
    const deployed = getAddress('0x1000000000000000000000000000000000000001')
    const transport = new FakeTransport()
    transport.storedReceipt = {
      transactionHash: txHash,
      blockNumber: 9n,
      status: 'success',
      contractAddress: deployed,
    }
    transport.code.set(deployed.toLowerCase(), '0x6000')
    const store = new MemoryProgressStore({
      'deploy-token': { txHash, status: 'submitted' },
    })
    const engine = new PlanExecutor(plan, transport, store)

    expect(await engine.resume()).toBe(1)
    expect(store.load()['deploy-token']).toEqual({
      txHash,
      blockNumber: 9,
      status: 'verified',
      resolvedAddress: deployed,
    })
  })

  it('recovers a mined compensating transaction before rechecking its transient predicate', async () => {
    const archController = getAddress('0x2000000000000000000000000000000000000002')
    const helper = getAddress('0x3000000000000000000000000000000000000003')
    const reclaimHash = `0x${'34'.repeat(32)}` as Hex
    const restoreHash = `0x${'56'.repeat(32)}` as Hex
    const ownershipPlan: DeploymentPlan = {
      ...plan,
      transactions: [
        {
          id: 'reclaim-owner',
          kind: 'call',
          description: 'Temporarily reclaim ownership.',
          reverifyUntil: 'restore-owner',
          to: helper,
          functionSignature: 'returnOwnership()',
          args: [],
          calldata: '0x',
          envelope: {
            chainId: plan.chainId,
            expectedExecutor: executor,
            to: helper,
            value: '0',
            data: 'functionSignature+args',
            gasLimitPolicy: 'estimate*1.3',
            nonceCheck: 'display-and-confirm',
          },
          predicate: {
            type: 'callEq',
            target: archController,
            call: { sig: 'owner() view returns (address)', args: [] },
            expect: executor,
          },
        },
        {
          id: 'restore-owner',
          kind: 'call',
          description: 'Restore helper ownership.',
          to: archController,
          functionSignature: 'transferOwnership(address)',
          args: [helper],
          calldata: '0x',
          envelope: {
            chainId: plan.chainId,
            expectedExecutor: executor,
            to: archController,
            value: '0',
            data: 'functionSignature+args',
            gasLimitPolicy: 'estimate*1.3',
            nonceCheck: 'display-and-confirm',
          },
          predicate: {
            type: 'callEq',
            target: archController,
            call: { sig: 'owner() view returns (address)', args: [] },
            expect: helper,
          },
        },
      ],
    }
    const transport = new FakeTransport()
    transport.storedReceipt = {
      transactionHash: restoreHash,
      blockNumber: 10n,
      status: 'success',
    }
    transport.callResult = encodeAbiParameters(parseAbiParameters('address'), [helper])
    const store = new MemoryProgressStore({
      'reclaim-owner': {
        txHash: reclaimHash,
        blockNumber: 9,
        status: 'verified',
      },
      'restore-owner': { txHash: restoreHash, status: 'submitted' },
    })
    const engine = new PlanExecutor(ownershipPlan, transport, store)

    expect(await engine.resume()).toBe(2)
    expect(store.load()['restore-owner']).toEqual({
      txHash: restoreHash,
      blockNumber: 10,
      status: 'verified',
    })
  })

  it('checks exact stored code in both runners, including STOP-only storage', async () => {
    const transport = new FakeTransport()
    const target = getAddress('0x1000000000000000000000000000000000000001')
    const outputs = new Map([['store', target]])
    for (const code of ['0x00', '0x006000', '0x6000'] as Hex[]) {
      const predicate: Predicate = { type: 'codeHash', target: { $ref: 'store' }, expect: keccak256(code) }
      for (const actual of [code, `${code}01` as Hex, '0x' as Hex]) {
        transport.code.set(target.toLowerCase(), actual)
        const ui = await evaluatePredicate(transport, predicate, outputs)
        const cli = await checkCliPredicate(async (method: string, params: string[]) => {
          expect(method).toBe('eth_getCode')
          expect(params).toEqual([target, 'latest'])
          return actual
        }, predicate, outputs)
        expect(ui).toEqual(cli)
        expect(ui.ok).toBe(actual === code)
      }
    }
  })

  it('requires a literal artifact hash in storage predicates', () => {
    const candidate = structuredClone(plan)
    candidate.transactions[0].predicate = { type: 'codeHash', target: { $ref: 'fixture-token' }, expect: keccak256('0x00') }
    expect(validatePlan(candidate, { checkArtifacts: false }).errors).toEqual([])
    for (const expectValue of [undefined, '0x1234', { $ref: 'fixture-token' }]) {
      candidate.transactions[0].predicate = { type: 'codeHash', target: { $ref: 'fixture-token' }, expect: expectValue } as Predicate
      expect(validatePlan(candidate, { checkArtifacts: false }).errors.length).toBeGreaterThan(0)
    }
    for (const extra of [
      { initCodeHash: '0x1234' },
      { call: { sig: 'owner() view returns (address)', args: [] } },
      { resultIndex: 0 },
    ]) {
      candidate.transactions[0].predicate = {
        type: 'codeHash', target: { $ref: 'fixture-token' }, expect: keccak256('0x00'), ...extra,
      } as Predicate
      expect(validatePlan(candidate, { checkArtifacts: false }).errors.length).toBeGreaterThan(0)
    }
    candidate.transactions[0].predicate = {
      type: 'codePresent', target: { $ref: 'fixture-token' }, initCodeHash: keccak256('0x00'),
    } as Predicate
    expect(validatePlan(candidate, { checkArtifacts: false }).errors).toContain(
      '$.transactions[0].predicate: initCodeHash requires codeHash or splitCodeHash',
    )
  })

  it('authenticates both split runtimes and their link before calling the reader', async () => {
    const target = getAddress('0x1000000000000000000000000000000000000001')
    const secondary = getAddress('0x2000000000000000000000000000000000000002')
    const original: Hex = '0xabcdef'
    const image: Hex = `0x600060005260206000f3abcd${'00'.repeat(20)}00020001`
    const linked = (image.slice(0, -48) + secondary.slice(2) + image.slice(-8)) as Hex
    const tail: Hex = '0x00ef'
    const predicate: Predicate = {
      type: 'splitCodeHash', target: { $ref: 'primary' }, expect: keccak256(image),
      secondary: { $ref: 'secondary' }, secondaryCodeHash: keccak256(tail),
      initCodeHash: keccak256(original),
    }
    const outputs = new Map([['primary', target], ['secondary', secondary]])
    const cases: [Hex, Hex, Hex, boolean, boolean][] = [
      [linked, tail, original, true, true],
      ['0x', tail, original, false, false],
      [`0xfe${linked.slice(4)}`, tail, original, false, false],
      [image, tail, original, false, false],
      [`${linked}00`, tail, original, false, false],
      [linked, '0x', original, false, false],
      [linked, '0x00ee', original, false, false],
      [linked, '0x00ef00', original, false, false],
      [linked, '0x60ef', original, false, false],
      [linked, tail, '0xfe', false, true],
    ]
    for (const [primaryCode, secondaryCode, returned, ok, shouldCall] of cases) {
      const transport = new FakeTransport()
      transport.code.set(target.toLowerCase(), primaryCode)
      transport.code.set(secondary.toLowerCase(), secondaryCode)
      let uiCalls = 0
      let cliCalls = 0
      transport.ethCall = async () => {
        uiCalls++
        if (!shouldCall) throw new Error('unverified store executed')
        return returned
      }
      const cli = await checkCliPredicate(async (method: string, params: any[]) => {
        if (method === 'eth_getCode') return transport.code.get(params[0].toLowerCase())
        cliCalls++
        if (!shouldCall) throw new Error('unverified store executed')
        return returned
      }, predicate, outputs)
      const ui = await evaluatePredicate(transport, predicate, outputs)
      expect(ui).toEqual(cli)
      expect(ui.ok).toBe(ok)
      expect(uiCalls).toBe(shouldCall ? 1 : 0)
      expect(cliCalls).toBe(uiCalls)
    }
  })

  it('requires complete split commitments and resolvable secondary references', () => {
    const candidate = structuredClone(plan)
    const valid: Predicate = {
      type: 'splitCodeHash', target: { $ref: 'fixture-token' }, expect: keccak256('0x60'),
      secondary: getAddress('0x2000000000000000000000000000000000000002'),
      secondaryCodeHash: keccak256('0x00'), initCodeHash: keccak256('0x'),
    }
    candidate.transactions[0].predicate = valid
    expect(validatePlan(candidate, { checkArtifacts: false }).errors).toEqual([])
    for (const field of ['expect', 'secondary', 'secondaryCodeHash', 'initCodeHash']) {
      const malformed = { ...valid } as any
      delete malformed[field]
      candidate.transactions[0].predicate = malformed
      expect(validatePlan(candidate, { checkArtifacts: false }).errors.length).toBeGreaterThan(0)
    }
    for (const extra of [
      { expect: { $ref: 'fixture-token' } },
      { secondary: { $ref: 'missing-secondary' } },
      { secondaryCodeHash: '0x12' },
      { call: { sig: 'owner() view returns (address)', args: [] } },
    ]) {
      candidate.transactions[0].predicate = { ...valid, ...extra } as Predicate
      expect(validatePlan(candidate, { checkArtifacts: false }).errors.length).toBeGreaterThan(0)
    }
  })

  it('checks decoded bytes only after authenticating the storage runtime', async () => {
    const target = getAddress('0x1000000000000000000000000000000000000001')
    for (const runtime of ['0x006000', '0x6000'] as Hex[]) {
      const transport = new FakeTransport()
      const original: Hex = '0x6000'
      const predicate: Predicate = {
        type: 'codeHash', target, expect: keccak256(runtime), initCodeHash: keccak256(original),
      }
      transport.code.set(target.toLowerCase(), runtime)
      transport.callResult = original
      const rpc = async (method: string) => method === 'eth_getCode' ? runtime : transport.callResult
      expect(await evaluatePredicate(transport, predicate, new Map())).toEqual(
        await checkCliPredicate(rpc, predicate, new Map()),
      )
      expect((await evaluatePredicate(transport, predicate, new Map())).ok).toBe(true)
      const wrong = { ...predicate, initCodeHash: keccak256('0xfe') }
      expect((await evaluatePredicate(transport, wrong, new Map())).ok).toBe(false)
      expect((await checkCliPredicate(rpc, wrong, new Map())).ok).toBe(false)
    }
    const predicate: Predicate = { type: 'codeHash', target, expect: keccak256('0x6000'), initCodeHash: keccak256('0x01') }
    const transport = new FakeTransport()
    transport.code.set(target.toLowerCase(), '0xfe')
    transport.ethCall = async () => { throw new Error('must not call an unverified reader') }
    expect((await evaluatePredicate(transport, predicate, new Map())).ok).toBe(false)
    expect((await checkCliPredicate(async (method: string) => {
      if (method !== 'eth_getCode') throw new Error('must not call an unverified reader')
      return '0xfe'
    }, predicate, new Map())).ok).toBe(false)
  })

  it('halts deployment after a stored-code hash mismatch and on resume', async () => {
    const candidate = structuredClone(plan)
    candidate.transactions[0].predicate = { type: 'codeHash', target: { $ref: 'fixture-token' }, expect: keccak256('0x6000') }
    const transport = new FakeTransport()
    transport.code.set('0x1000000000000000000000000000000000000001', '0xfe')
    const store = new MemoryProgressStore()
    const engine = new PlanExecutor(candidate, transport, store)
    const prepared = await engine.prepareNext()
    if (!prepared) throw new Error('expected deployment')
    await expect(engine.execute(prepared)).rejects.toThrow('code hash mismatch')
    transport.storedReceipt = await transport.waitForReceipt()
    await expect(engine.resume()).rejects.toThrow('code hash mismatch')
    expect(store.load()['deploy-token'].status).not.toBe('verified')
  })

  it('evaluates codePresent and call predicates exactly like plan.js', async () => {
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

    transport.callResult = encodeAbiParameters(parseAbiParameters('address,uint48'), [
      target,
      1234,
    ])
    expect(
      (
        await evaluatePredicate(
          transport,
          {
            type: 'callResultEq',
            target,
            call: { sig: 'pendingDefaultAdmin() view returns (address,uint48)', args: [] },
            resultIndex: 0,
            expect: target,
          },
          new Map(),
        )
      ).ok,
    ).toBe(true)
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

  it('rechecks completed steps concurrently and halts on the earliest failure in plan order', async () => {
    const targets = Array.from({ length: 8 }, (_, index) =>
      getAddress(`0x${(index + 1).toString(16).padStart(40, '0')}`),
    )
    const candidate = structuredClone(plan)
    candidate.transactions = targets.map((target, index) => ({
      ...structuredClone(plan.transactions[0]),
      id: `check-${index}`,
      predicate: { type: 'codePresent', target },
    }))
    const state: RunState = Object.fromEntries(
      candidate.transactions.map((transaction) => [
        transaction.id,
        { txHash: `0x${'ab'.repeat(32)}` as Hex, status: 'verified' as const },
      ]),
    )
    class SlowTransport extends FakeTransport {
      inFlight = 0
      peak = 0
      async getCode(address: Address) {
        this.inFlight += 1
        this.peak = Math.max(this.peak, this.inFlight)
        await new Promise((resolve) => setTimeout(resolve, 5))
        this.inFlight -= 1
        return super.getCode(address)
      }
    }
    const transport = new SlowTransport()
    for (const target of targets) transport.code.set(target.toLowerCase(), '0x6000')

    const resumed = new PlanExecutor(candidate, transport, new MemoryProgressStore(state))
    expect(await resumed.resume()).toBe(targets.length)
    expect(transport.peak).toBeGreaterThan(1)
    expect(transport.peak).toBeLessThanOrEqual(REVERIFY_CONCURRENCY)

    transport.code.delete(targets[5].toLowerCase())
    transport.code.delete(targets[2].toLowerCase())
    const halted = new PlanExecutor(candidate, transport, new MemoryProgressStore(state))
    await expect(halted.resume()).rejects.toThrow('prior predicate failed for check-2')
  })
})

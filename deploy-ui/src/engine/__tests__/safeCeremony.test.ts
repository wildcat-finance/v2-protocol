import { describe, expect, it, vi } from 'vitest'
import { keccak256, stringToHex } from 'viem'
import miniPlanJson from '../../../../scripts/__fixtures__/plan/mini-plan.json'
import { compileSafePlan, compileSafeTransactionData } from '../safeCompiler'
import { SafeCeremony, validateBundleArtifacts } from '../safeCeremony'
import { MemoryProgressStore } from '../runState'
import type { BundleManifest, DeploymentPlan } from '../types'

const plan = miniPlanJson as DeploymentPlan
const planHash = keccak256(stringToHex(JSON.stringify(miniPlanJson)))

function manifest(sourcePlan = plan, sourcePlanHash = planHash): BundleManifest {
  const compiled = compileSafePlan(sourcePlan)
  return {
    schemaVersion: '1.1.0',
    plan: {
      release: sourcePlan.release,
      network: sourcePlan.network,
      chainId: sourcePlan.chainId,
      fileHash: sourcePlanHash,
    },
    safe: { address: sourcePlan.expectedExecutor, version: '1.4.1' },
    bundle: {
      number: 1,
      safeNonce: '7',
      maxGas: '20000000',
      staticGasEstimate: '1',
      simulatedGas: null,
    },
    safeTransaction: {
      ...compileSafeTransactionData(
        sourcePlan.chainId,
        sourcePlan.expectedExecutor,
        7n,
        compiled.entries,
      ),
    },
    innerTransactions: compiled.entries.map((entry) => ({
      ...entry,
      staticGasEstimate: '1',
      simulatedGas: null,
    })),
  }
}

describe('Safe bundle artifact validation', () => {
  it('accepts exact plan coverage and expected addresses', () => {
    const value = manifest()
    const expected = compileSafePlan(plan).expectedAddresses
    expect(validateBundleArtifacts(plan, planHash, [value], expected)).toHaveLength(1)
  })

  it('rejects a non-DELEGATECALL outer Safe operation', () => {
    const value = manifest()
    ;(value.safeTransaction as { operation: number }).operation = 0
    expect(() =>
      validateBundleArtifacts(plan, planHash, [value], compileSafePlan(plan).expectedAddresses),
    ).toThrow('DELEGATECALL')
  })

  it('rejects outer Safe calldata that was not compiled from the plan', () => {
    const value = manifest()
    value.safeTransaction.data = '0x12'
    expect(() =>
      validateBundleArtifacts(plan, planHash, [value], compileSafePlan(plan).expectedAddresses),
    ).toThrow('Safe transaction does not match the plan compiler')
  })

  it('rejects a mutated Safe nonce or transaction hash', () => {
    const value = manifest()
    value.safeTransaction.nonce = '8'
    expect(() =>
      validateBundleArtifacts(plan, planHash, [value], compileSafePlan(plan).expectedAddresses),
    ).toThrow('Safe transaction does not match the plan compiler')
  })

  it('rejects mutated inner transaction data even when plan coverage is unchanged', () => {
    const value = manifest()
    value.innerTransactions[0].data = '0x12'
    expect(() =>
      validateBundleArtifacts(plan, planHash, [value], compileSafePlan(plan).expectedAddresses),
    ).toThrow(`${value.innerTransactions[0].planId}.data does not match the plan compiler`)
  })

  it('rejects expected deployment addresses that were not compiled from the plan', () => {
    const value = manifest()
    const expected = compileSafePlan(plan).expectedAddresses
    expected[value.innerTransactions[0].planId] =
      '0x0000000000000000000000000000000000000001'
    expect(() => validateBundleArtifacts(plan, planHash, [value], expected)).toThrow(
      'expected-addresses.json does not match addresses compiled from the plan',
    )
  })

  it('rejects unsimulated bundles for a mainnet plan', () => {
    const mainnetPlan = structuredClone(plan)
    mainnetPlan.network = 'mainnet'
    mainnetPlan.chainId = 1
    for (const transaction of mainnetPlan.transactions) transaction.envelope.chainId = 1
    const mainnetPlanHash = keccak256(stringToHex(JSON.stringify(mainnetPlan)))
    const value = manifest(mainnetPlan, mainnetPlanHash)
    expect(() =>
      validateBundleArtifacts(
        mainnetPlan,
        mainnetPlanHash,
        [value],
        compileSafePlan(mainnetPlan).expectedAddresses,
      ),
    ).toThrow('must include successful fork-simulated gas before mainnet use')
  })
})

describe('Safe Transaction Service cross-checks', () => {
  function engine(serviceTransaction: Record<string, unknown>) {
    const value = manifest()
    const owners = [
      plan.expectedExecutor,
      '0x0000000000000000000000000000000000000002',
      '0x0000000000000000000000000000000000000003',
    ]
    const createTransaction = vi.fn(async ({ options }: { options: { nonce: number } }) => {
      expect(options.nonce).toBe(7)
      return { data: value.safeTransaction, signatures: new Map() }
    })
    const serviceResponse = {
      safe: plan.expectedExecutor,
      to: value.safeTransaction.to,
      value: value.safeTransaction.value,
      data: value.safeTransaction.data,
      operation: value.safeTransaction.operation,
      gasToken: value.safeTransaction.gasToken,
      safeTxGas: value.safeTransaction.safeTxGas,
      baseGas: value.safeTransaction.baseGas,
      gasPrice: value.safeTransaction.gasPrice,
      refundReceiver: value.safeTransaction.refundReceiver,
      nonce: value.safeTransaction.nonce,
      safeTxHash: value.safeTransaction.safeTxHash,
      confirmationsRequired: 3,
      confirmations: [],
      isExecuted: false,
      transactionHash: null,
      ...serviceTransaction,
    }
    return new SafeCeremony(
      plan,
      planHash,
      [value],
      compileSafePlan(plan).expectedAddresses,
      {
        getChainId: async () => plan.chainId,
        getCode: async () => '0x01',
        ethCall: async () => '0x',
        waitForReceipt: async () => { throw new Error('not used') },
        getReceipt: async () => null,
      },
      {
        createTransaction,
        executeTransaction: async () => { throw new Error('not used') },
        getAddress: async () => plan.expectedExecutor,
        getContractVersion: () => '1.4.1',
        getNonce: async () => 7,
        getOwners: async () => owners,
        getSafeProvider: () => ({ getSignerAddress: async () => plan.expectedExecutor }),
        getThreshold: async () => 3,
        getTransactionHash: async () => value.safeTransaction.safeTxHash,
        signHash: async () => { throw new Error('not used') },
        signTransaction: async () => { throw new Error('not used') },
      } as never,
      {
        getTransaction: async () => serviceResponse,
        confirmTransaction: async () => { throw new Error('not used') },
        proposeTransaction: async () => { throw new Error('not used') },
      } as never,
      new MemoryProgressStore(),
    )
  }

  it('accepts service data that exactly matches the compiled transaction', async () => {
    await expect(engine({}).getProgress(0)).resolves.toMatchObject({
      confirmations: 0,
      threshold: 3,
      executed: false,
    })
  })

  it('rejects service calldata or hash that differs from the compiled transaction', async () => {
    await expect(engine({ data: '0x12' }).getProgress(0)).rejects.toThrow(
      'does not match compiled bundle',
    )
    await expect(engine({ safeTxHash: `0x${'12'.repeat(32)}` }).getProgress(0)).rejects.toThrow(
      'does not match compiled bundle',
    )
  })

  it('rejects a service threshold that differs from the Safe', async () => {
    await expect(engine({
      confirmationsRequired: 1,
    }).getProgress(0)).rejects.toThrow('does not match on-chain threshold')
  })

  it('rejects confirmations attributed to a non-owner', async () => {
    await expect(engine({
      confirmations: [{ owner: '0x0000000000000000000000000000000000000004' }],
    }).getProgress(0)).rejects.toThrow('confirmation from non-owner')
  })
})

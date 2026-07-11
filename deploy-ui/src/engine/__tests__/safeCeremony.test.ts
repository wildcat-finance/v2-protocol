import { describe, expect, it } from 'vitest'
import { keccak256, stringToHex, type Hex } from 'viem'
import miniPlanJson from '../../../../scripts/__fixtures__/plan/mini-plan.json'
import { validateBundleArtifacts } from '../safeCeremony'
import type { BundleManifest, DeploymentPlan } from '../types'

const plan = miniPlanJson as DeploymentPlan
const planHash = keccak256(stringToHex(JSON.stringify(miniPlanJson)))

function manifest(): BundleManifest {
  return {
    schemaVersion: '1.0.0',
    plan: {
      release: plan.release,
      network: plan.network,
      chainId: plan.chainId,
      fileHash: planHash,
    },
    safe: { address: plan.expectedExecutor, version: '1.4.1' },
    bundle: {
      number: 1,
      maxGas: '20000000',
      staticGasEstimate: '1',
      simulatedGas: null,
    },
    safeTransaction: {
      to: '0x38869bf66a61cF6bDB996A6aE40D5853Fd43B526',
      value: '0',
      data: '0x12',
      operation: 1,
    },
    innerTransactions: plan.transactions.map((transaction, planIndex) => ({
      planIndex,
      planId: transaction.id,
      kind: transaction.kind,
      description: transaction.description,
      operation: transaction.kind === 'deploy' ? 1 : 0,
      to: plan.expectedExecutor,
      logicalTarget: plan.expectedExecutor,
      value: '0',
      data: '0x12' as Hex,
      decodedArgs: [],
      predicate: transaction.predicate,
      precomputedAddress:
        transaction.kind === 'deploy'
          ? (`0x${String(planIndex + 1).padStart(40, '0')}` as `0x${string}`)
          : null,
      salt: null,
      initCodeHash: null,
      staticGasEstimate: '1',
      simulatedGas: null,
    })),
  }
}

describe('Safe bundle artifact validation', () => {
  it('accepts exact plan coverage and expected addresses', () => {
    const value = manifest()
    const expected = Object.fromEntries(
      value.innerTransactions
        .filter((entry) => entry.precomputedAddress)
        .map((entry) => [entry.planId, entry.precomputedAddress!]),
    )
    expect(validateBundleArtifacts(plan, planHash, [value], expected)).toHaveLength(1)
  })

  it('rejects a non-DELEGATECALL outer Safe operation', () => {
    const value = manifest()
    ;(value.safeTransaction as { operation: number }).operation = 0
    expect(() => validateBundleArtifacts(plan, planHash, [value], {})).toThrow(
      'DELEGATECALL',
    )
  })
})

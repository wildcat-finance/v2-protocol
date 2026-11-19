import { execFileSync } from 'node:child_process'
import { createRequire } from 'node:module'
import { mkdtempSync, readFileSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join, resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { encodeFunctionData, keccak256, parseAbi, stringToHex } from 'viem'
import miniPlanJson from '../../../../scripts/__fixtures__/plan/mini-plan.json'
import { assertCeremonyPackage, assertPlan } from '../../artifacts'

interface ArtifactCandidate {
  artifact: {
    abi: unknown[]
    bytecode: { object: string; linkReferences: Record<string, unknown> }
    deployedBytecode: { object: string }
    rawMetadata: string
  }
  filePath: string
  sourceName: string
  contractName: string
}

const ROOT = resolve(import.meta.dirname, '../../../..')
const require = createRequire(import.meta.url)
const { collapseDuplicateArtifactCandidates } =
  require('../../../../scripts/plan.js') as {
    collapseDuplicateArtifactCandidates: (
      candidates: ArtifactCandidate[],
      artifactName: string,
    ) => ArtifactCandidate[]
  }

function artifactCandidate(
  sourceName: string,
  filePath: string,
  bytecode = '0x6000',
): ArtifactCandidate {
  return {
    artifact: {
      abi: [],
      bytecode: { object: bytecode, linkReferences: {} },
      deployedBytecode: { object: '0x00' },
      rawMetadata: '{"sources":{}}',
    },
    filePath,
    sourceName,
    contractName: 'MockERC20',
  }
}

function canonicalJson(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(',')}]`
  if (value !== null && typeof value === 'object') {
    return `{${Object.keys(value)
      .sort()
      .map((key) => `${JSON.stringify(key)}:${canonicalJson((value as Record<string, unknown>)[key])}`)
      .join(',')}}`
  }
  return JSON.stringify(value)
}

function eoaPackage() {
  const json = `${JSON.stringify(miniPlanJson, null, 2)}\n`
  const payload = {
    mode: 'eoa',
    release: miniPlanJson.release,
    network: miniPlanJson.network,
    chainId: miniPlanJson.chainId,
    artifacts: {
      plan: { name: 'mini-plan.json', hash: keccak256(stringToHex(json)), json },
      manifests: [],
      expectedAddresses: null,
    },
  }
  return {
    schemaVersion: '1.0.0',
    digest: keccak256(stringToHex(canonicalJson(payload))),
    payload,
  }
}

describe('Foundry artifact resolution', () => {
  it('collapses duplicate files for the same compiled artifact identity', () => {
    const source = 'script/mock/MockERC20.sol'
    const candidates = [
      artifactCandidate(source, '/tmp/first/MockERC20.json'),
      artifactCandidate(source, '/tmp/second/MockERC20.json'),
    ]

    expect(
      collapseDuplicateArtifactCandidates(
        candidates,
        'script/mock/MockERC20.sol:MockERC20',
      ),
    ).toEqual([candidates[0]])
  })

  it('rejects conflicting compiled copies of the same artifact identity', () => {
    const source = 'script/mock/MockERC20.sol'
    const candidate = artifactCandidate(source, '/tmp/first/MockERC20.json')
    const conflicting = artifactCandidate(
      source,
      '/tmp/second/MockERC20.json',
      '0x6001',
    )

    expect(() =>
      collapseDuplicateArtifactCandidates(
        [candidate, conflicting],
        'script/mock/MockERC20.sol:MockERC20',
      ),
    ).toThrow('has conflicting compiled copies')
  })

  it('keeps artifacts from different source contracts distinct', () => {
    const candidates = [
      artifactCandidate(
        'script/mock/MockERC20.sol',
        '/tmp/script/MockERC20.json',
      ),
      artifactCandidate(
        'lib/example/MockERC20.sol',
        '/tmp/library/MockERC20.json',
      ),
    ]

    expect(collapseDuplicateArtifactCandidates(candidates, 'MockERC20')).toEqual(
      candidates,
    )
  })
})

describe('embedded ceremony packages', () => {
  it('validates its digest and exact packaged plan bytes', () => {
    const loaded = assertCeremonyPackage(eoaPackage())
    expect(loaded.mode).toBe('eoa')
    expect(loaded.plan.value.transactions).toHaveLength(3)
    expect(loaded.fingerprint).toMatch(/^[A-F0-9]{4}(?:-[A-F0-9]{4}){2}$/)
  })

  it('rejects artifact mutation even if the outer envelope is otherwise valid', () => {
    const value = eoaPackage()
    value.payload.artifacts.plan.json += ' '
    value.digest = keccak256(stringToHex(canonicalJson(value.payload)))
    expect(() => assertCeremonyPackage(value)).toThrow('packaged bytes do not match artifact hash')
  })

  it('rejects a known network paired with the wrong chain ID', () => {
    const plan = structuredClone(miniPlanJson)
    plan.network = 'sepolia'
    expect(() => assertPlan(plan)).toThrow('network sepolia requires chain ID 11155111')
  })

  it('accepts a package emitted by the Node release compiler', () => {
    const directory = mkdtempSync(join(tmpdir(), 'ceremony-package-'))
    const planPath = join(directory, 'call-only-plan.json')
    const packagePath = join(directory, 'ceremony.json')
    const executor = '0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266'
    const target = '0x0000000000000000000000000000000000000001'
    const functionSignature = 'owner() view returns (address)'
    const calldata = encodeFunctionData({
      abi: parseAbi([`function ${functionSignature}`]),
      functionName: 'owner',
    })
    writeFileSync(planPath, `${JSON.stringify({
      schemaVersion: '1.1.0',
      foundryProfile: 'deploy',
      network: 'anvil',
      chainId: 31337,
      release: 'package-test',
      expectedExecutor: executor,
      onFailure: 'halt',
      resume: 're-verify all prior predicates before continuing',
      transactions: [{
        id: 'call-owner',
        kind: 'call',
        description: 'Exercise package compilation.',
        to: target,
        functionSignature,
        args: [],
        calldata,
        envelope: {
          chainId: 31337,
          expectedExecutor: executor,
          to: target,
          value: '0',
          data: 'functionSignature+args',
          gasLimitPolicy: 'estimate*1.3',
          nonceCheck: 'display-and-confirm',
        },
        predicate: { type: 'codePresent', target },
      }],
    }, null, 2)}\n`)
    execFileSync(
      'node',
      [
        'scripts/plan.js',
        'ceremony-package',
        '--plan',
        planPath,
        '--mode',
        'eoa',
        '--out',
        packagePath,
      ],
      {
        cwd: ROOT,
        env: { ...process.env, FOUNDRY_PROFILE: 'deploy' },
      },
    )
    const loaded = assertCeremonyPackage(JSON.parse(readFileSync(packagePath, 'utf8')))
    expect(loaded.plan.value.release).toBe('package-test')
  })
})

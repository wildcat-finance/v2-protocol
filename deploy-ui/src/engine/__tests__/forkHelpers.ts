import {
  execFileSync,
  spawn,
  type ChildProcessWithoutNullStreams,
} from 'node:child_process'
import { readFileSync } from 'node:fs'
import { join, resolve } from 'node:path'
import {
  createPublicClient,
  createWalletClient,
  http,
  type Address,
  type Hex,
} from 'viem'
import { privateKeyToAccount } from 'viem/accounts'
import type { ExecutionTransport, ReceiptLike } from '../types'
import type { DeploymentPlan } from '../types'

export const DEV_KEY =
  '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80' as Hex

interface FoundryArtifactCache {
  files?: Record<string, { artifacts?: Record<string, unknown> }>
}

function collectArtifactPaths(
  value: unknown,
  paths = new Set<string>(),
): Set<string> {
  if (Array.isArray(value)) {
    for (const entry of value) collectArtifactPaths(entry, paths)
  } else if (value !== null && typeof value === 'object') {
    const record = value as Record<string, unknown>
    if (typeof record.path === 'string') paths.add(record.path)
    for (const entry of Object.values(record)) collectArtifactPaths(entry, paths)
  }
  return paths
}

function currentArtifactPath(
  root: string,
  outDirectory: string,
  cache: FoundryArtifactCache,
  sourceName: string,
  contractName: string,
): string {
  const paths = [
    ...collectArtifactPaths(cache.files?.[sourceName]?.artifacts?.[contractName]),
  ]
  if (paths.length !== 1) {
    throw new Error(
      `Expected one deploy-profile artifact for ${sourceName}:${contractName}; found ${paths.length}. Run npm run test:fork from deploy-ui.`,
    )
  }
  return resolve(root, outDirectory, paths[0])
}

export function withCurrentFixtureBytecode(
  fixture: DeploymentPlan,
  root: string,
): DeploymentPlan {
  const plan = structuredClone(fixture)
  const config = JSON.parse(
    execFileSync('forge', ['config', '--json'], {
      cwd: root,
      encoding: 'utf8',
      env: { ...process.env, FOUNDRY_PROFILE: 'deploy' },
    }),
  ) as { out: string; cache_path: string }
  const cache = JSON.parse(
    readFileSync(join(root, config.cache_path, 'solidity-files-cache.json'), 'utf8'),
  ) as FoundryArtifactCache
  const artifacts: Record<
    string,
    { name: string; sourceName: string; contractName: string }
  > = {
    'deploy-token': {
      name: 'script/mock/MockERC20.sol:MockERC20',
      sourceName: 'script/mock/MockERC20.sol',
      contractName: 'MockERC20',
    },
    'deploy-market': {
      name: 'test/mocks/LensMocks.sol:LensV1MarketMock',
      sourceName: 'test/mocks/LensMocks.sol',
      contractName: 'LensV1MarketMock',
    },
  }
  for (const transaction of plan.transactions) {
    if (transaction.kind !== 'deploy') continue
    const currentArtifact = artifacts[transaction.id]
    if (!currentArtifact) continue
    const artifactPath = currentArtifactPath(
      root,
      config.out,
      cache,
      currentArtifact.sourceName,
      currentArtifact.contractName,
    )
    const artifact = JSON.parse(readFileSync(artifactPath, 'utf8')) as {
      bytecode: { object: Hex }
    }
    transaction.artifactName = currentArtifact.name
    transaction.initCode = artifact.bytecode.object
  }
  return plan
}

export async function startAnvil(
  forkUrl: string,
  port: number,
): Promise<{ process: ChildProcessWithoutNullStreams; url: string }> {
  const child = spawn(
    'anvil',
    [
      '--fork-url',
      forkUrl,
      '--host',
      '127.0.0.1',
      '--port',
      String(port),
      '--chain-id',
      '31337',
      '--silent',
    ],
    { stdio: 'pipe' },
  )
  const url = `http://127.0.0.1:${port}`
  let output = ''
  child.stderr.on('data', (chunk) => {
    output += String(chunk)
  })
  for (let attempt = 0; attempt < 120; attempt += 1) {
    if (child.exitCode !== null) throw new Error(`Anvil exited early: ${output}`)
    try {
      const response = await fetch(url, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'eth_chainId', params: [] }),
      })
      if (response.ok) return { process: child, url }
    } catch {
      // Anvil is still starting.
    }
    await new Promise((resolve) => setTimeout(resolve, 250))
  }
  child.kill('SIGTERM')
  throw new Error(`Timed out starting Anvil: ${output}`)
}

export async function stopAnvil(child: ChildProcessWithoutNullStreams): Promise<void> {
  if (child.exitCode !== null) return
  child.kill('SIGTERM')
  await Promise.race([
    new Promise<void>((resolve) => child.once('exit', () => resolve())),
    new Promise<void>((resolve) => setTimeout(resolve, 2_000)),
  ])
  if (child.exitCode === null) child.kill('SIGKILL')
}

export function nodeExecutionTransport(rpcUrl: string): ExecutionTransport {
  const account = privateKeyToAccount(DEV_KEY)
  const publicClient = createPublicClient({ transport: http(rpcUrl) })
  const walletClient = createWalletClient({ account, transport: http(rpcUrl) })

  function receipt(value: {
    transactionHash: Hex
    blockNumber: bigint
    status: 'success' | 'reverted'
    contractAddress?: Address | null
  }): ReceiptLike {
    return {
      transactionHash: value.transactionHash,
      blockNumber: value.blockNumber,
      status: value.status,
      contractAddress: value.contractAddress,
    }
  }

  return {
    getChainId: () => publicClient.getChainId(),
    getAccount: async () => account.address,
    getCode: (address) => publicClient.getCode({ address }),
    getTransactionCount: (address) =>
      publicClient.getTransactionCount({ address, blockTag: 'pending' }),
    estimateGas: (request) => publicClient.estimateGas(request),
    sendTransaction: (request) => walletClient.sendTransaction({ ...request, chain: null }),
    waitForReceipt: async (hash) =>
      receipt(await publicClient.waitForTransactionReceipt({ hash })),
    getReceipt: async (hash) => {
      try {
        return receipt(await publicClient.getTransactionReceipt({ hash }))
      } catch {
        return null
      }
    },
    ethCall: async (to, data) => {
      const result = await publicClient.call({ to, data })
      if (!result.data) throw new Error(`eth_call returned no data for ${to}.`)
      return result.data
    },
  }
}

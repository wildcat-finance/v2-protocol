import { spawn, type ChildProcessWithoutNullStreams } from 'node:child_process'
import { readFileSync } from 'node:fs'
import { join } from 'node:path'
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

export function withCurrentFixtureBytecode(
  fixture: DeploymentPlan,
  root: string,
): DeploymentPlan {
  const plan = structuredClone(fixture)
  const artifacts: Record<string, string> = {
    'deploy-token': join(root, 'deploy-out/mock/MockERC20.sol/MockERC20.json'),
    'deploy-market': join(root, 'deploy-out/MarketLens.t.sol/MockV1MarketLike.json'),
  }
  for (const transaction of plan.transactions) {
    if (transaction.kind !== 'deploy') continue
    const artifactPath = artifacts[transaction.id]
    if (!artifactPath) continue
    const artifact = JSON.parse(readFileSync(artifactPath, 'utf8')) as {
      bytecode: { object: Hex }
    }
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

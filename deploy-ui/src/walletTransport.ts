import {
  createPublicClient,
  createWalletClient,
  custom,
  getAddress,
  TransactionReceiptNotFoundError,
  type Address,
  type EIP1193Provider,
  type Hex,
} from 'viem'
import type { ExecutionTransport, ReceiptLike } from './engine/types'

export function injectedProvider(): EIP1193Provider {
  const provider = (window as Window & { ethereum?: EIP1193Provider }).ethereum
  if (!provider) throw new Error('No injected wallet provider was found.')
  return provider
}

export function browserExecutionTransport(account: Address): ExecutionTransport {
  const transport = custom(injectedProvider())
  const publicClient = createPublicClient({ transport })
  const walletClient = createWalletClient({ account, transport })

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
    getAccount: async () => getAddress(account),
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
      } catch (error) {
        if (error instanceof TransactionReceiptNotFoundError) return null
        throw error
      }
    },
    ethCall: async (to, data) => {
      const result = await publicClient.call({ to, data })
      if (!result.data) throw new Error(`eth_call returned no data for ${to}.`)
      return result.data
    },
  }
}

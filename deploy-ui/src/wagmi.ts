import { createConfig, http } from 'wagmi'
import { foundry, mainnet, sepolia } from 'wagmi/chains'
import { injected } from 'wagmi/connectors'

export const wagmiConfig = createConfig({
  chains: [mainnet, sepolia, foundry],
  connectors: [injected({ shimDisconnect: true })],
  transports: {
    [mainnet.id]: http(import.meta.env.VITE_MAINNET_RPC_URL),
    [sepolia.id]: http(import.meta.env.VITE_SEPOLIA_RPC_URL),
    [foundry.id]: http(import.meta.env.VITE_ANVIL_RPC_URL || 'http://127.0.0.1:8545'),
  },
})

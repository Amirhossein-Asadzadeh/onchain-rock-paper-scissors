import { getDefaultConfig } from '@rainbow-me/rainbowkit'
import { sepolia } from 'wagmi/chains'

export const config = getDefaultConfig({
  appName: 'Rock Paper Scissors',
  projectId: import.meta.env.VITE_WALLETCONNECT_PROJECT_ID ?? 'placeholder',
  chains: [sepolia],
  ssr: false,
})

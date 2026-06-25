import { formatEther } from 'viem'

export const fmtEth = (wei: bigint) =>
  `${parseFloat(formatEther(wei)).toFixed(4)} ETH`

export const fmtAddr = (addr: string) =>
  `${addr.slice(0, 6)}…${addr.slice(-4)}`

export const fmtTime = (ts: bigint) =>
  new Date(Number(ts) * 1000).toLocaleString()

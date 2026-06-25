import { useEffect } from 'react'
import { useAccount, useReadContract, useWriteContract, useWaitForTransactionReceipt } from 'wagmi'
import { RPS_ABI } from '../abi'
import { CONTRACT_ADDRESS } from '../constants'
import { fmtEth } from '../lib/format'

export function WithdrawBar() {
  const { address, isConnected } = useAccount()

  const { data: pending, refetch } = useReadContract({
    address: CONTRACT_ADDRESS,
    abi: RPS_ABI,
    functionName: 'pendingWithdrawals',
    args: [address!],
    query: {
      enabled: isConnected && !!address,
      refetchInterval: 10_000,
    },
  })

  const { writeContract, data: txHash, isPending } = useWriteContract()
  const { isLoading, isSuccess } = useWaitForTransactionReceipt({ hash: txHash })

  useEffect(() => {
    if (isSuccess) refetch()
  }, [isSuccess, refetch])

  if (!isConnected || !pending || pending === 0n) return null

  return (
    <button
      onClick={() =>
        writeContract({ address: CONTRACT_ADDRESS, abi: RPS_ABI, functionName: 'withdraw' })
      }
      disabled={isPending || isLoading}
      className="flex items-center gap-2 px-3 py-1.5 rounded-lg bg-emerald-700 hover:bg-emerald-600 disabled:opacity-50 disabled:cursor-not-allowed text-sm font-medium transition-colors"
    >
      💰 {fmtEth(pending)} — Withdraw
    </button>
  )
}

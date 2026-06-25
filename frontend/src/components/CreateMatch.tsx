import { useState, useEffect, useRef } from 'react'
import { useAccount, useWriteContract, useWaitForTransactionReceipt } from 'wagmi'
import { parseEther, decodeEventLog } from 'viem'
import { RPS_ABI } from '../abi'
import { CONTRACT_ADDRESS, MOVES } from '../constants'
import { makeCommitment, randomSalt } from '../lib/commitment'
import { saveCommit } from '../lib/storage'

type Props = { onCreated: (matchId: string) => void }

export function CreateMatch({ onCreated }: Props) {
  const { address, isConnected } = useAccount()
  const [move, setMove] = useState<number | null>(null)
  const [stakeEth, setStakeEth] = useState('0.001')
  const [pendingCommit, setPendingCommit] = useState<{ move: number; salt: `0x${string}` } | null>(null)
  const [createdId, setCreatedId] = useState<string | null>(null)
  const processedHash = useRef<string | null>(null)

  const { writeContract, data: txHash, isPending: isWriting, error: writeError, reset } = useWriteContract()
  const { isLoading: isConfirming, isSuccess, data: receipt } = useWaitForTransactionReceipt({ hash: txHash })

  // After the tx confirms, decode the MatchCreated log to get the matchId
  useEffect(() => {
    if (!isSuccess || !receipt || !pendingCommit || !address) return
    if (processedHash.current === txHash) return
    processedHash.current = txHash ?? null

    for (const log of receipt.logs) {
      try {
        const { args } = decodeEventLog({
          abi: RPS_ABI,
          data: log.data,
          topics: log.topics,
          eventName: 'MatchCreated',
        })
        const id = (args as { matchId: bigint }).matchId.toString()
        saveCommit(address, id, pendingCommit.move, pendingCommit.salt)
        setCreatedId(id)
        onCreated(id)
        setPendingCommit(null)
        break
      } catch {
        // not the MatchCreated log, skip
      }
    }
  }, [isSuccess, receipt, txHash, address, pendingCommit, onCreated])

  const handleCreate = () => {
    if (!address || move === null) return
    const salt = randomSalt()
    const commitment = makeCommitment(move, salt, address)
    setPendingCommit({ move, salt })
    setCreatedId(null)
    reset()
    processedHash.current = null
    writeContract({
      address: CONTRACT_ADDRESS,
      abi: RPS_ABI,
      functionName: 'createMatch',
      args: [commitment],
      value: parseEther(stakeEth),
    })
  }

  return (
    <Card title="Create a Match">
      {!isConnected ? (
        <p className="text-slate-400 text-sm">Connect your wallet to create a match.</p>
      ) : (
        <div className="space-y-4">
          {/* Move picker */}
          <div>
            <label className="text-xs text-slate-400 mb-2 block">Your move (secret until both reveal)</label>
            <div className="flex gap-2">
              {MOVES.map(m => (
                <button
                  key={m.value}
                  onClick={() => setMove(m.value)}
                  title={m.label}
                  className={`flex-1 py-3 rounded-lg text-2xl transition-all border ${
                    move === m.value
                      ? 'ring-2 ring-indigo-500 bg-slate-700 border-indigo-500'
                      : 'bg-slate-800 border-slate-700 hover:bg-slate-700'
                  }`}
                >
                  {m.emoji}
                </button>
              ))}
            </div>
            {move !== null && (
              <p className="text-xs text-slate-500 mt-1">
                {MOVES.find(m => m.value === move)?.label} selected — your commitment is hashed on-chain
              </p>
            )}
          </div>

          {/* Stake input */}
          <div>
            <label className="text-xs text-slate-400 mb-2 block">Stake (ETH per player)</label>
            <input
              type="number"
              min="0"
              step="0.001"
              value={stakeEth}
              onChange={e => setStakeEth(e.target.value)}
              className="w-full bg-slate-800 border border-slate-700 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-1 focus:ring-indigo-500"
            />
            <p className="text-xs text-slate-500 mt-1">Opponent must send exactly this amount to join.</p>
          </div>

          <button
            onClick={handleCreate}
            disabled={move === null || isWriting || isConfirming}
            className="w-full py-2 rounded-lg bg-indigo-600 hover:bg-indigo-700 disabled:opacity-50 disabled:cursor-not-allowed text-sm font-medium transition-colors"
          >
            {isWriting ? 'Confirm in wallet…' : isConfirming ? 'Confirming…' : 'Create Match'}
          </button>

          {writeError && (
            <p className="text-red-400 text-xs break-all">
              {(writeError as { shortMessage?: string }).shortMessage ?? writeError.message}
            </p>
          )}

          {createdId !== null && (
            <div className="rounded-lg bg-emerald-900/30 border border-emerald-700/50 p-3 space-y-1">
              <p className="text-emerald-400 text-sm font-medium">Match created!</p>
              <p className="text-slate-300 text-xs">
                ID:{' '}
                <span className="font-mono font-bold text-white text-sm">{createdId}</span>
              </p>
              <p className="text-slate-400 text-xs">
                Share this ID with your opponent. The match appears on the right.
              </p>
            </div>
          )}
        </div>
      )}
    </Card>
  )
}

function Card({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="bg-slate-900 border border-slate-800 rounded-xl p-5">
      <h2 className="text-base font-semibold mb-4">{title}</h2>
      {children}
    </div>
  )
}

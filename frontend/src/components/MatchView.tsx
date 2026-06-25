import { useState, useEffect, useRef } from 'react'
import { useAccount, useReadContract, useWriteContract, useWaitForTransactionReceipt } from 'wagmi'
import { RPS_ABI } from '../abi'
import { CONTRACT_ADDRESS, MOVES, STATE_LABELS, STATE_COLORS, ZERO_ADDRESS } from '../constants'
import { makeCommitment, randomSalt } from '../lib/commitment'
import { saveCommit, loadCommit, clearCommit } from '../lib/storage'
import { fmtEth, fmtAddr, fmtTime } from '../lib/format'

type Props = {
  matchId: string
  onMatchIdChange: (id: string) => void
}

export function MatchView({ matchId, onMatchIdChange }: Props) {
  const [inputId, setInputId] = useState(matchId)
  const { address, isConnected } = useAccount()

  useEffect(() => { setInputId(matchId) }, [matchId])

  const { data: match, refetch } = useReadContract({
    address: CONTRACT_ADDRESS,
    abi: RPS_ABI,
    functionName: 'getMatch',
    args: [BigInt(matchId || '0')],
    query: {
      enabled: matchId !== '',
      refetchInterval: 5_000,
    },
  })

  const now = BigInt(Math.floor(Date.now() / 1000))
  const isP1 = !!(address && match && address.toLowerCase() === match.player1.toLowerCase())
  const isP2 = !!(address && match && address.toLowerCase() === match.player2.toLowerCase())

  // ── Stored commit (from when this player created/joined) ─────────────────
  const storedCommit = address && matchId ? loadCommit(address, matchId) : null
  const canReveal =
    !!match &&
    (isP1 || isP2) &&
    (match.state === 1 || match.state === 2) &&
    now <= match.revealDeadline &&
    ((isP1 && !match.revealed1) || (isP2 && !match.revealed2))

  // ── Reveal ───────────────────────────────────────────────────────────────
  const revealWrite = useWriteContract()
  const revealReceipt = useWaitForTransactionReceipt({ hash: revealWrite.data })
  const revealProcessed = useRef<string | null>(null)

  useEffect(() => {
    if (!revealReceipt.isSuccess || revealProcessed.current === revealWrite.data) return
    revealProcessed.current = revealWrite.data ?? null
    if (address && matchId) clearCommit(address, matchId)
    refetch()
  }, [revealReceipt.isSuccess, revealWrite.data, address, matchId, refetch])

  const handleReveal = () => {
    if (!storedCommit || !matchId) return
    revealWrite.writeContract({
      address: CONTRACT_ADDRESS,
      abi: RPS_ABI,
      functionName: 'reveal',
      args: [BigInt(matchId), storedCommit.move, storedCommit.salt as `0x${string}`],
    })
  }

  // ── Join ─────────────────────────────────────────────────────────────────
  const [joinMove, setJoinMove] = useState<number | null>(null)
  const [pendingJoinCommit, setPendingJoinCommit] = useState<{ move: number; salt: `0x${string}` } | null>(null)
  const joinWrite = useWriteContract()
  const joinReceipt = useWaitForTransactionReceipt({ hash: joinWrite.data })
  const joinProcessed = useRef<string | null>(null)

  useEffect(() => {
    if (!joinReceipt.isSuccess || joinProcessed.current === joinWrite.data) return
    joinProcessed.current = joinWrite.data ?? null
    if (address && matchId && pendingJoinCommit) {
      saveCommit(address, matchId, pendingJoinCommit.move, pendingJoinCommit.salt)
    }
    setPendingJoinCommit(null)
    refetch()
  }, [joinReceipt.isSuccess, joinWrite.data, address, matchId, pendingJoinCommit, refetch])

  const handleJoin = () => {
    if (!address || joinMove === null || !match || !matchId) return
    const salt = randomSalt()
    const commitment = makeCommitment(joinMove, salt, address)
    setPendingJoinCommit({ move: joinMove, salt })
    joinWrite.writeContract({
      address: CONTRACT_ADDRESS,
      abi: RPS_ABI,
      functionName: 'joinMatch',
      args: [BigInt(matchId), commitment],
      value: match.stake,
    })
  }

  // ── Cancel ───────────────────────────────────────────────────────────────
  const cancelWrite = useWriteContract()
  const cancelReceipt = useWaitForTransactionReceipt({ hash: cancelWrite.data })
  useEffect(() => { if (cancelReceipt.isSuccess) refetch() }, [cancelReceipt.isSuccess, refetch])

  // ── Resolve expired ──────────────────────────────────────────────────────
  const resolveWrite = useWriteContract()
  const resolveReceipt = useWaitForTransactionReceipt({ hash: resolveWrite.data })
  useEffect(() => { if (resolveReceipt.isSuccess) refetch() }, [resolveReceipt.isSuccess, refetch])

  const moveEmoji = (mv: number) => MOVES.find(m => m.value === mv)?.emoji ?? '?'

  return (
    <div className="bg-slate-900 border border-slate-800 rounded-xl p-5 space-y-4">
      <h2 className="text-base font-semibold">Find a Match</h2>

      {/* ID lookup */}
      <div className="flex gap-2">
        <input
          type="number"
          min="0"
          placeholder="Match ID"
          value={inputId}
          onChange={e => setInputId(e.target.value)}
          className="flex-1 bg-slate-800 border border-slate-700 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-1 focus:ring-indigo-500"
        />
        <button
          onClick={() => onMatchIdChange(inputId)}
          className="px-4 py-2 bg-slate-700 hover:bg-slate-600 rounded-lg text-sm transition-colors"
        >
          Look up
        </button>
      </div>

      {matchId !== '' && !match && (
        <p className="text-slate-500 text-sm">Loading…</p>
      )}

      {match && (
        <div className="space-y-3">
          {/* State badge + role */}
          <div className="flex items-center gap-2 flex-wrap">
            <span className={`text-xs px-2 py-0.5 rounded-full font-medium border ${STATE_COLORS[match.state]}`}>
              {STATE_LABELS[match.state]}
            </span>
            {(isP1 || isP2) && (
              <span className="text-xs text-slate-500">You are {isP1 ? 'Player 1' : 'Player 2'}</span>
            )}
          </div>

          {/* Match details */}
          <div className="text-sm space-y-1.5 text-slate-300">
            <Row label="Player 1">
              <span className="font-mono text-xs">{fmtAddr(match.player1)}</span>
            </Row>
            <Row label="Player 2">
              {match.player2 === ZERO_ADDRESS ? (
                <span className="text-slate-500 text-xs italic">waiting…</span>
              ) : (
                <span className="font-mono text-xs">{fmtAddr(match.player2)}</span>
              )}
            </Row>
            <Row label="Stake per player">
              <span className="font-medium">{fmtEth(match.stake)}</span>
            </Row>
            {match.state === 0 && (
              <Row label="Join deadline">
                <span className="text-xs text-slate-400">{fmtTime(match.joinDeadline)}</span>
              </Row>
            )}
            {(match.state === 1 || match.state === 2) && (
              <Row label="Reveal deadline">
                <span className="text-xs text-slate-400">{fmtTime(match.revealDeadline)}</span>
              </Row>
            )}
          </div>

          {/* Reveal status */}
          {(match.state === 1 || match.state === 2) && (
            <div className="flex gap-4 text-xs border-t border-slate-800 pt-3">
              <span className={match.revealed1 ? 'text-emerald-400' : 'text-slate-500'}>
                {match.revealed1 ? '✅' : '⏳'} P1
              </span>
              <span className={match.revealed2 ? 'text-emerald-400' : 'text-slate-500'}>
                {match.revealed2 ? '✅' : '⏳'} P2
              </span>
            </div>
          )}

          {/* Resolved: show moves */}
          {match.state === 3 && (
            <div className="text-sm space-y-1 border-t border-slate-800 pt-3">
              <Row label="P1 played"><span className="text-lg">{moveEmoji(match.move1)}</span></Row>
              <Row label="P2 played"><span className="text-lg">{moveEmoji(match.move2)}</span></Row>
            </div>
          )}

          {/* ── Actions ─────────────────────────────────────────────── */}

          {/* JOIN */}
          {match.state === 0 && isConnected && !isP1 && now <= match.joinDeadline && (
            <div className="border-t border-slate-800 pt-3 space-y-3">
              <p className="text-sm text-slate-300">
                Join for <strong>{fmtEth(match.stake)}</strong>
              </p>
              <div>
                <label className="text-xs text-slate-400 mb-1 block">Your move</label>
                <div className="flex gap-2">
                  {MOVES.map(m => (
                    <button
                      key={m.value}
                      onClick={() => setJoinMove(m.value)}
                      className={`flex-1 py-2 rounded-lg text-xl transition-all border ${
                        joinMove === m.value
                          ? 'ring-2 ring-indigo-500 bg-slate-700 border-indigo-500'
                          : 'bg-slate-800 border-slate-700 hover:bg-slate-700'
                      }`}
                    >
                      {m.emoji}
                    </button>
                  ))}
                </div>
              </div>
              <Btn
                onClick={handleJoin}
                disabled={joinMove === null || joinWrite.isPending || joinReceipt.isLoading}
                loading={joinWrite.isPending || joinReceipt.isLoading}
                label={`Join for ${fmtEth(match.stake)}`}
              />
              <TxError err={joinWrite.error} />
            </div>
          )}

          {/* CANCEL */}
          {match.state === 0 && isP1 && now > match.joinDeadline && (
            <div className="border-t border-slate-800 pt-3 space-y-2">
              <p className="text-xs text-slate-400">No one joined before the deadline.</p>
              <Btn
                onClick={() => cancelWrite.writeContract({ address: CONTRACT_ADDRESS, abi: RPS_ABI, functionName: 'cancelMatch', args: [BigInt(matchId)] })}
                disabled={cancelWrite.isPending || cancelReceipt.isLoading}
                loading={cancelWrite.isPending || cancelReceipt.isLoading}
                label="Cancel & Recover Stake"
                variant="danger"
              />
              <TxError err={cancelWrite.error} />
            </div>
          )}

          {/* REVEAL */}
          {canReveal && (
            <div className="border-t border-slate-800 pt-3 space-y-2">
              {storedCommit ? (
                <>
                  <p className="text-xs text-slate-400">
                    Your committed move:{' '}
                    <span className="text-xl">{moveEmoji(storedCommit.move)}</span>
                  </p>
                  <Btn
                    onClick={handleReveal}
                    disabled={revealWrite.isPending || revealReceipt.isLoading}
                    loading={revealWrite.isPending || revealReceipt.isLoading}
                    label="Reveal Move"
                  />
                </>
              ) : (
                <p className="text-xs text-amber-400">
                  Move not found in browser storage. If you committed from a different device
                  or cleared your storage, you cannot reveal here without the original move
                  and salt.
                </p>
              )}
              <TxError err={revealWrite.error} />
            </div>
          )}

          {/* RESOLVE EXPIRED */}
          {(match.state === 1 || match.state === 2) && now > match.revealDeadline && (
            <div className="border-t border-slate-800 pt-3 space-y-2">
              <p className="text-xs text-slate-400">Reveal deadline passed.</p>
              <Btn
                onClick={() => resolveWrite.writeContract({ address: CONTRACT_ADDRESS, abi: RPS_ABI, functionName: 'resolveExpired', args: [BigInt(matchId)] })}
                disabled={resolveWrite.isPending || resolveReceipt.isLoading}
                loading={resolveWrite.isPending || resolveReceipt.isLoading}
                label="Settle Expired Match"
                variant="warning"
              />
              <TxError err={resolveWrite.error} />
            </div>
          )}
        </div>
      )}
    </div>
  )
}

function Row({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="flex justify-between items-center">
      <span className="text-slate-400">{label}</span>
      {children}
    </div>
  )
}

function Btn({
  onClick, disabled, loading, label, variant = 'primary',
}: {
  onClick: () => void
  disabled: boolean
  loading: boolean
  label: string
  variant?: 'primary' | 'danger' | 'warning'
}) {
  const colors = {
    primary: 'bg-indigo-600 hover:bg-indigo-700',
    danger:  'bg-red-700    hover:bg-red-600',
    warning: 'bg-amber-700  hover:bg-amber-600',
  }
  return (
    <button
      onClick={onClick}
      disabled={disabled}
      className={`w-full py-2 rounded-lg text-sm font-medium transition-colors disabled:opacity-50 disabled:cursor-not-allowed ${colors[variant]}`}
    >
      {loading ? 'Confirming…' : label}
    </button>
  )
}

function TxError({ err }: { err: Error | null }) {
  if (!err) return null
  return (
    <p className="text-red-400 text-xs break-all">
      {(err as { shortMessage?: string }).shortMessage ?? err.message}
    </p>
  )
}

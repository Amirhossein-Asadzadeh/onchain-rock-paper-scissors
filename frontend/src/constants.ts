export const CONTRACT_ADDRESS = (
  import.meta.env.VITE_CONTRACT_ADDRESS ?? '0xeD82F40B46BEACBE18098b8c2fbbd8cD7a513ab0'
) as `0x${string}`

export const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000'

export const MOVES = [
  { value: 1, label: 'Rock',     emoji: '🪨' },
  { value: 2, label: 'Paper',    emoji: '📄' },
  { value: 3, label: 'Scissors', emoji: '✂️' },
] as const

// Matches the MatchState enum order in the contract
export const STATE_LABELS = ['Created', 'Active', 'Revealing', 'Resolved', 'Cancelled'] as const

export const STATE_COLORS = [
  'text-yellow-400 bg-yellow-400/10 border-yellow-400/20',  // Created
  'text-blue-400   bg-blue-400/10   border-blue-400/20',    // Active
  'text-purple-400 bg-purple-400/10 border-purple-400/20',  // Revealing
  'text-emerald-400 bg-emerald-400/10 border-emerald-400/20', // Resolved
  'text-slate-400  bg-slate-400/10  border-slate-400/20',   // Cancelled
] as const

// Persists a player's {move, salt} between the commit and reveal steps.
// Keyed by wallet address + match ID so multiple matches don't collide.
// If the user clears browser storage they lose the ability to reveal — the
// MatchView shows a warning in that case.

type Commit = { move: number; salt: string }

const key = (addr: string, matchId: string) =>
  `rps:${addr.toLowerCase()}:${matchId}`

export const saveCommit = (addr: string, matchId: string, move: number, salt: string) =>
  localStorage.setItem(key(addr, matchId), JSON.stringify({ move, salt }))

export const loadCommit = (addr: string, matchId: string): Commit | null => {
  try {
    const raw = localStorage.getItem(key(addr, matchId))
    return raw ? (JSON.parse(raw) as Commit) : null
  } catch {
    return null
  }
}

export const clearCommit = (addr: string, matchId: string) =>
  localStorage.removeItem(key(addr, matchId))

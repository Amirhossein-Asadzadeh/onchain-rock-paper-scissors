import { useState } from 'react'
import { ConnectButton } from '@rainbow-me/rainbowkit'
import { CreateMatch } from './components/CreateMatch'
import { MatchView } from './components/MatchView'
import { WithdrawBar } from './components/WithdrawBar'

export default function App() {
  // matchId lifted here so CreateMatch can auto-populate the MatchView after creation
  const [matchId, setMatchId] = useState('')

  return (
    <div className="min-h-screen bg-slate-950 text-slate-100">
      <header className="border-b border-slate-800 px-6 py-4 flex items-center gap-4">
        <span className="text-2xl select-none">✂️</span>
        <h1 className="text-lg font-semibold flex-1">Rock Paper Scissors</h1>
        <WithdrawBar />
        <ConnectButton />
      </header>

      <main className="max-w-5xl mx-auto p-6 grid grid-cols-1 md:grid-cols-2 gap-6 items-start">
        <CreateMatch onCreated={setMatchId} />
        <MatchView matchId={matchId} onMatchIdChange={setMatchId} />
      </main>

      <footer className="text-center text-xs text-slate-600 py-8">
        On Sepolia testnet ·{' '}
        <a
          href="https://sepolia.etherscan.io/address/0xeD82F40B46BEACBE18098b8c2fbbd8cD7a513ab0"
          target="_blank"
          rel="noopener noreferrer"
          className="underline hover:text-slate-400"
        >
          View contract
        </a>
      </footer>
    </div>
  )
}

# Rock Paper Scissors — On-Chain Staked Matches

[![CI](https://github.com/Amirhossein-Asadzadeh/onchain-rock-paper-scissors/actions/workflows/ci.yml/badge.svg)](https://github.com/Amirhossein-Asadzadeh/onchain-rock-paper-scissors/actions/workflows/ci.yml)

A two-player, staked Rock-Paper-Scissors game on any EVM chain, using a
commit-reveal scheme so neither player can see the other's move before committing.

**Stack:** Solidity 0.8.24 · Foundry · OpenZeppelin ReentrancyGuard

---

## Game Flow

### 1. Player 1 creates a match

```bash
# Off-chain: generate your commitment
cast keccak $(cast abi-encode "f(uint8,bytes32,address)" 1 0xMYSALT $MY_ADDRESS)

# On-chain: stake + commit
cast send $CONTRACT "createMatch(bytes32)" 0xMYCOMMIT --value 0.1ether
```

The contract emits `MatchCreated(matchId, player1, stake, joinDeadline)`.
Player 1's stake is locked. If no one joins within `JOIN_TIMEOUT` (24 hours),
Player 1 can call `cancelMatch(matchId)` to recover their stake.

### 2. Player 2 joins

```bash
cast send $CONTRACT "joinMatch(uint256,bytes32)" $MATCH_ID 0xP2COMMIT --value 0.1ether
```

Player 2 must send exactly the same stake. Self-play is rejected.
The `REVEAL_TIMEOUT` (24 hours) starts now.

### 3. Both players reveal

```bash
# Move enum: Rock=1, Paper=2, Scissors=3
cast send $CONTRACT "reveal(uint256,uint8,bytes32)" $MATCH_ID 1 0xMYSALT
```

Each player submits their move and salt. The contract recomputes
`keccak256(abi.encodePacked(move, salt, msg.sender))` and verifies it matches
the commitment. Order doesn't matter — whoever hasn't revealed yet goes second.

When the second player reveals, `_settle()` runs immediately:
- **Win:** winner's `pendingWithdrawals` increases by `2 × stake`.
- **Tie:** each player's `pendingWithdrawals` increases by `stake`.

### 4. Withdraw

```bash
cast send $CONTRACT "withdraw()"
```

Pull pattern — the contract never pushes ETH. Winners call `withdraw()` to
collect their pending balance at any time after settlement.

---

## Timeout Paths

### No second player (join timeout)

After `JOIN_TIMEOUT` passes with the match in `Created` state, Player 1 calls:

```bash
cast send $CONTRACT "cancelMatch(uint256)" $MATCH_ID
```

Their stake is credited to `pendingWithdrawals`.

### One player didn't reveal (reveal timeout)

After `REVEAL_TIMEOUT` passes, anyone calls:

```bash
cast send $CONTRACT "resolveExpired(uint256)" $MATCH_ID
```

- **One player revealed, other didn't:** the player who revealed wins both stakes.
- **Neither revealed:** both stakes are refunded.

Making `resolveExpired` callable by anyone ensures liveness — a relayer or the
opponent can settle without waiting for the other party.

---

## State Machine

```
createMatch()
      │
      ▼
   Created  ──(after joinDeadline)──► cancelMatch()  ──► Cancelled
      │
joinMatch()
      │
      ▼
   Active   ──(after revealDeadline)─► resolveExpired() ──► Resolved / Cancelled
      │
first reveal()
      │
      ▼
  Revealing ──(after revealDeadline)─► resolveExpired() ──► Resolved
      │
second reveal()
      │
      ▼
  Resolved ──► pendingWithdrawals[] ──► withdraw()
```

---

## Security Design

| Property | Implementation |
|---|---|
| Move secrecy | Commit-reveal: hash includes `msg.sender`, so P2 can't reuse P1's hash |
| No front-running | P2 commits before seeing P1's move; P1 reveals after |
| Reentrancy | `nonReentrant` + CEI ordering on all fund-moving functions |
| Pull payment | `withdraw()` only; no ETH push from contract |
| Timestamp | Used only for 24h deadlines; miner manipulation (~±15s) is negligible |
| Self-play | Rejected — player can't join their own match |

---

## Running the Tests

```bash
# Install dependencies (first time)
foundryup
forge install

# Compile
forge build

# Run all tests
forge test -v

# Run with verbose traces (useful for debugging)
forge test -vvvv

# Run only fuzz tests
forge test --match-contract "Fuzz" -v

# Run invariant tests
forge test --match-contract "Invariant" -v

# Coverage report
forge coverage --report summary

# Gas snapshot
forge snapshot
```

### Test coverage

```
src/RockPaperScissors.sol   99% lines · 97.5% statements · 100% functions
```

### What each test covers

| Suite | Tests | Covers |
|---|---|---|
| `RPS_CreateMatch_Test` | 6 | Data storage, event, ETH receipt, zero-stake revert, zero-commitment revert |
| `RPS_JoinMatch_Test` | 10 | Data storage, event, combined balance, self-play, wrong stake, after deadline, wrong state, non-existent match, zero-commitment |
| `RPS_Reveal_Test` | 21 | All 9 RPS outcomes (3 P1 wins, 3 P2 wins, 3 ties) with event verification; state transitions; both players can go first; wrong move/salt/address/phase reverts; double-reveal revert |
| `RPS_Cancel_Test` | 7 | Happy path with withdraw; before-deadline revert; wrong-caller revert; wrong-state revert; exactly-at-deadline boundary; one-second-after boundary |
| `RPS_ResolveExpired_Test` | 10 | P1-revealed-wins; P2-revealed-wins; neither-revealed-both-refund; anyone-can-call; before-deadline revert; exactly-at-deadline boundary; double-call revert; wrong-state reverts |
| `RPS_Withdraw_Test` | 7 | Winner collects full pot; tie both collect; event; zero-balance revert; double-withdraw revert; balance accounting; reentrancy blocked |
| `RPS_Fuzz_Test` | 6 (×1000 runs each) | All move combinations produce correct winner; wrong salt always fails; wrong move always fails; stake matching; commitment address-binding; concurrent match independence |
| `RPS_Invariant_Test` | 3 (256 runs × 64 calls) | `balance == locked + pending`; ETH conservation; no pending exceeds total staked |

---

## Commit-Reveal Reference

```solidity
// Compute your commitment off-chain:
bytes32 commitment = keccak256(abi.encodePacked(move, salt, msg.sender));

// Or use the on-chain helper (gas cost, but useful for testing):
bytes32 commitment = rps.commitHash(Move.Rock, mySalt, msg.sender);
```

Move values: `None=0`, `Rock=1`, `Paper=2`, `Scissors=3`.
`None` is rejected on reveal.

Salt should be a random 32-byte value generated off-chain and kept secret until
reveal time. Never reuse a salt across matches.

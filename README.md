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

## Deploying to Sepolia Testnet

Sepolia is an EVM test network where you can deploy and interact with contracts
using free, worthless ETH. No money is at risk.

---

### Background: what is a private key, and why a throwaway?

Every Ethereum account is controlled by a **private key** — a random 256-bit
number from which your wallet address is mathematically derived. Whoever holds
the private key controls the account.

When you deploy a contract, you sign the deployment transaction with your
private key. Foundry's `vm.envUint("PRIVATE_KEY")` reads that key from your
environment at deploy time — it never appears in any source file.

**Why a dedicated throwaway wallet, not your real one?**

- Testnet tooling (shell history, `.env` backups, CI logs) has many places a
  private key can leak. If it's a throwaway with only testnet ETH, a leak is
  harmless. If it's your real wallet, you lose real money.
- Keeping testnet and mainnet wallets entirely separate is basic operational
  security. Get into the habit now.

---

### Step 1 — Create a fresh throwaway wallet

`cast wallet new` generates a new random key pair and prints both the address
and the private key:

```bash
cast wallet new
```

Output looks like:

```
Successfully created new keypair.
Address:     0xAbCd...1234
Private key: 0xdeadbeef...
```

**Save the private key for the next steps, then discard it after experimenting.
Never reuse this wallet for anything important.**

---

### Step 2 — Get free Sepolia ETH

You need a small amount of Sepolia ETH to pay gas for the deployment
transaction. It costs nothing real — it is testnet fuel.

1. Copy the address printed by `cast wallet new`.
2. Visit one of these faucets and paste your address:
   - [sepoliafaucet.com](https://sepoliafaucet.com) (Alchemy, requires login)
   - [faucet.sepolia.dev](https://faucet.sepolia.dev) (Google login)
   - [infura.io/faucet/sepolia](https://www.infura.io/faucet/sepolia) (Infura)
3. Verify the balance arrived (~30 seconds):
   ```bash
   cast balance YOUR_ADDRESS --rpc-url https://rpc.sepolia.org
   ```
   You should see something like `500000000000000000` (0.5 ETH in wei).

---

### Step 3 — Get a Sepolia RPC endpoint

You need an HTTP URL that gives you access to a Sepolia node:

| Provider | Free tier | Sign-up |
|---|---|---|
| Alchemy  | 300M compute units/month | [dashboard.alchemy.com](https://dashboard.alchemy.com) |
| Infura   | 100k requests/day        | [app.infura.io](https://app.infura.io) |
| Public   | Rate-limited, no sign-up | `https://rpc.sepolia.org` |

After creating an app on Alchemy or Infura, copy the Sepolia HTTP URL — it
looks like `https://eth-sepolia.g.alchemy.com/v2/xxxxxxxxxx`.

---

### Step 4 — Get an Etherscan API key

Required for source code verification (Step 6). Free account at
[etherscan.io/register](https://etherscan.io/register) → **API Keys** → **Add**.
The same key works for both mainnet and Sepolia Etherscan.

---

### Step 5 — Fill in `.env`

```bash
cp .env.example .env
```

Open `.env` and replace the placeholders with your real values:

```bash
SEPOLIA_RPC_URL=https://eth-sepolia.g.alchemy.com/v2/YOUR_KEY
PRIVATE_KEY=0xYOUR_THROWAWAY_PRIVATE_KEY
ETHERSCAN_API_KEY=YOUR_ETHERSCAN_KEY
```

Confirm `.env` is git-ignored before proceeding — you only need to do this
once:

```bash
grep '\.env' .gitignore    # should print ".env" and ".env.*"
```

---

### Step 6 — Deploy and verify

Load your env vars, then run the deployment script:

```bash
source .env

forge script script/Deploy.s.sol \
  --rpc-url sepolia \
  --broadcast \
  --verify \
  -vvvv
```

**What each flag does:**

| Flag | Meaning |
|---|---|
| `--rpc-url sepolia` | Looks up `sepolia` in `[rpc_endpoints]` in `foundry.toml`, which expands to `$SEPOLIA_RPC_URL` |
| `--broadcast` | Actually submits the transaction on-chain. Without it, Foundry only dry-runs — nothing is deployed |
| `--verify` | After deployment, submits your Solidity source to Etherscan so anyone can read and audit it |
| `-vvvv` | Verbose — prints the full call trace so you can see exactly what happened |

**What `--verify` does and why it matters for a portfolio project:**

When you deploy compiled bytecode, anyone can see the bytecode on-chain but
cannot read the original Solidity. `--verify` submits your source code to
Etherscan, which recompiles it and confirms the bytecode matches. After
verification, the contract page shows a green checkmark, the full source, and
an interactive UI for calling functions — extremely useful for demonstrating
the project to anyone reviewing your portfolio.

Successful output ends with something like:

```
== Logs ==
  RockPaperScissors deployed at: 0xAbCd...1234

...
Contract successfully verified.
```

---

### Step 7 — Confirm on Sepolia Etherscan

1. Open `https://sepolia.etherscan.io/address/0xYOUR_CONTRACT_ADDRESS`.
2. The **Contract** tab should have a green checkmark ("Contract Source Code
   Verified"), plus **Read Contract** and **Write Contract** tabs for live
   interaction.
3. Click **Write Contract** → connect MetaMask (Sepolia network) → call
   `createMatch` to play a live on-chain game.

---

### Broadcast receipts

Every `--broadcast` run writes a JSON receipt to `broadcast/`:

```
broadcast/
  Deploy.s.sol/
    11155111/          ← Sepolia chain ID
      run-latest.json  ← deployed address, tx hash, block number
```

This directory is git-ignored. To share the deployed address, copy it from
Forge's terminal output or from `run-latest.json`.

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

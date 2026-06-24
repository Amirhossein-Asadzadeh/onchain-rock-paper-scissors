// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title  RockPaperScissors
/// @notice Two-player staked RPS with commit-reveal and a pull-payment pattern.
///
/// ── State machine (per match) ──────────────────────────────────────────────
///
///   createMatch(commitment)
///         │
///         ▼
///      Created  ──(joinDeadline passes, no P2)──► cancelMatch()
///         │                                            │
///   joinMatch(commitment)                              ▼
///         │                                        Cancelled
///         ▼
///       Active  ──(revealDeadline passes)──► resolveExpired()
///         │                                       │
///   first reveal()                     one revealed → Resolved (winner)
///         │                            neither     → Cancelled (refunds)
///         ▼
///      Revealing
///         │
///   second reveal()
///         │
///         ▼
///      Resolved  ──► pendingWithdrawals[] ──► withdraw()
///
/// ── Self-play policy ───────────────────────────────────────────────────────
///   A player may NOT join their own match.  joinMatch reverts with SelfPlay().
///   Rationale: a player playing themselves already knows both moves, making
///   the game trivially determined and committing stakes pointlessly.
///
/// ── Timestamp trust assumption ─────────────────────────────────────────────
///   block.timestamp is used only for join/reveal deadlines, never for
///   randomness.  Miners can shift it by ~±15 seconds; for 24-hour windows
///   this is negligible.  Do not reduce timeouts below ~30 minutes on mainnet.
///
contract RockPaperScissors is ReentrancyGuard {
    // ── Types ────────────────────────────────────────────────────────────────

    enum Move { None, Rock, Paper, Scissors }

    enum MatchState {
        Created,    // P1 staked + committed; waiting for P2
        Active,     // both committed; reveal window open
        Revealing,  // first player revealed; second pending
        Resolved,   // stakes paid out (win or tie)
        Cancelled   // terminated; stakes refundable
    }

    struct Match {
        address    player1;
        address    player2;
        uint256    stake;           // per player; total pot = 2 * stake
        bytes32    commitment1;
        bytes32    commitment2;
        Move       move1;
        Move       move2;
        bool       revealed1;
        bool       revealed2;
        MatchState state;
        uint256    joinDeadline;    // P2 must join before this timestamp
        uint256    revealDeadline;  // both must reveal before this timestamp
    }

    // ── Constants ────────────────────────────────────────────────────────────

    uint256 public constant JOIN_TIMEOUT   = 24 hours;
    uint256 public constant REVEAL_TIMEOUT = 24 hours;

    // ── Storage ──────────────────────────────────────────────────────────────

    uint256 private _matchCount;

    mapping(uint256 => Match)   public matches;
    mapping(address => uint256) public pendingWithdrawals;

    // ── Events ───────────────────────────────────────────────────────────────

    event MatchCreated(
        uint256 indexed matchId,
        address indexed player1,
        uint256         stake,
        uint256         joinDeadline
    );
    event PlayerJoined(
        uint256 indexed matchId,
        address indexed player2,
        uint256         revealDeadline
    );
    // Move intentionally omitted from MoveRevealed — once one player reveals,
    // the other can see it on-chain, but there is no benefit in logging it a
    // second time before both are visible together in MatchResolved.
    event MoveRevealed(uint256 indexed matchId, address indexed player);
    event MatchResolved(
        uint256 indexed matchId,
        address indexed winner,  // address(0) = tie
        Move            move1,
        Move            move2
    );
    event MatchCancelled(uint256 indexed matchId);
    event Withdrawn(address indexed player, uint256 amount);

    // ── Custom errors (cheaper than require-strings) ──────────────────────────

    error MatchNotFound(uint256 matchId);
    error WrongState(MatchState current);
    error DeadlineNotPassed();
    error DeadlinePassed();
    error WrongStake(uint256 sent, uint256 required);
    error ZeroCommitment();
    error SelfPlay();
    error NotParticipant();
    error NotPlayer1();
    error AlreadyRevealed();
    error CommitMismatch();
    error InvalidMove();
    error NoFundsToWithdraw();

    // ── External: match lifecycle ─────────────────────────────────────────────

    /// @notice Create a new match.  The ETH sent becomes the required stake.
    /// @param  commitment  keccak256(abi.encodePacked(move, salt, msg.sender))
    /// @return matchId     Sequential ID for the new match.
    function createMatch(bytes32 commitment)
        external
        payable
        returns (uint256 matchId)
    {
        if (msg.value == 0)           revert WrongStake(msg.value, 1);
        if (commitment == bytes32(0)) revert ZeroCommitment();

        matchId = _matchCount++;

        // Writes happen before any external interaction — CEI compliant.
        matches[matchId] = Match({
            player1:      msg.sender,
            player2:      address(0),
            stake:        msg.value,
            commitment1:  commitment,
            commitment2:  bytes32(0),
            move1:        Move.None,
            move2:        Move.None,
            revealed1:    false,
            revealed2:    false,
            state:        MatchState.Created,
            joinDeadline: block.timestamp + JOIN_TIMEOUT,
            revealDeadline: 0
        });

        emit MatchCreated(matchId, msg.sender, msg.value, block.timestamp + JOIN_TIMEOUT);
    }

    /// @notice Join an open match.  Must send exactly the same stake as P1.
    /// @param  commitment  keccak256(abi.encodePacked(move, salt, msg.sender))
    function joinMatch(uint256 matchId, bytes32 commitment) external payable {
        if (matchId >= _matchCount)               revert MatchNotFound(matchId);
        Match storage m = matches[matchId];

        if (m.state != MatchState.Created)        revert WrongState(m.state);
        if (block.timestamp > m.joinDeadline)     revert DeadlinePassed();
        if (msg.sender == m.player1)              revert SelfPlay();
        if (msg.value != m.stake)                 revert WrongStake(msg.value, m.stake);
        if (commitment == bytes32(0))             revert ZeroCommitment();

        // Effects
        m.player2       = msg.sender;
        m.commitment2   = commitment;
        m.state         = MatchState.Active;
        m.revealDeadline = block.timestamp + REVEAL_TIMEOUT;

        emit PlayerJoined(matchId, msg.sender, m.revealDeadline);
    }

    /// @notice Reveal your committed move.  Both players must call this within
    ///         REVEAL_TIMEOUT after P2 joined.  The second reveal settles the match.
    function reveal(uint256 matchId, Move move, bytes32 salt) external {
        if (matchId >= _matchCount)   revert MatchNotFound(matchId);
        Match storage m = matches[matchId];

        if (m.state != MatchState.Active && m.state != MatchState.Revealing) {
            revert WrongState(m.state);
        }
        if (block.timestamp > m.revealDeadline) revert DeadlinePassed();
        if (move == Move.None)                  revert InvalidMove();

        bool isP1 = (msg.sender == m.player1);
        bool isP2 = (msg.sender == m.player2);
        if (!isP1 && !isP2) revert NotParticipant();

        // Verify the commitment and record the reveal — checks then effects.
        if (isP1) {
            if (m.revealed1) revert AlreadyRevealed();
            if (keccak256(abi.encodePacked(move, salt, msg.sender)) != m.commitment1)
                revert CommitMismatch();
            m.move1     = move;
            m.revealed1 = true;
        } else {
            if (m.revealed2) revert AlreadyRevealed();
            if (keccak256(abi.encodePacked(move, salt, msg.sender)) != m.commitment2)
                revert CommitMismatch();
            m.move2     = move;
            m.revealed2 = true;
        }

        emit MoveRevealed(matchId, msg.sender);

        if (m.revealed1 && m.revealed2) {
            // Both revealed: settle immediately.
            _settle(matchId, m);
        } else {
            // First reveal: advance state.
            m.state = MatchState.Revealing;
        }
        // No external calls here; ETH moves only through withdraw().
    }

    /// @notice Settle a match after the reveal deadline has passed.
    ///         - One player revealed → that player wins both stakes.
    ///         - Neither revealed    → both stakes are refunded.
    ///         Callable by anyone; outcome is deterministic from on-chain state.
    function resolveExpired(uint256 matchId) external nonReentrant {
        if (matchId >= _matchCount) revert MatchNotFound(matchId);
        Match storage m = matches[matchId];

        if (m.state != MatchState.Active && m.state != MatchState.Revealing) {
            revert WrongState(m.state);
        }
        if (block.timestamp <= m.revealDeadline) revert DeadlineNotPassed();

        bool p1 = m.revealed1;
        bool p2 = m.revealed2;

        if (p1 && !p2) {
            // P2 timed out after P1 revealed → P1 wins.
            m.state = MatchState.Resolved;
            pendingWithdrawals[m.player1] += 2 * m.stake;
            emit MatchResolved(matchId, m.player1, m.move1, Move.None);
        } else if (!p1 && p2) {
            // P1 timed out after P2 revealed → P2 wins.
            m.state = MatchState.Resolved;
            pendingWithdrawals[m.player2] += 2 * m.stake;
            emit MatchResolved(matchId, m.player2, Move.None, m.move2);
        } else {
            // Neither revealed (or both — impossible here because _settle() would
            // have already moved state to Resolved).  Refund both.
            m.state = MatchState.Cancelled;
            pendingWithdrawals[m.player1] += m.stake;
            pendingWithdrawals[m.player2] += m.stake;
            emit MatchCancelled(matchId);
        }
    }

    /// @notice Player 1 cancels their match if no one has joined within JOIN_TIMEOUT.
    function cancelMatch(uint256 matchId) external nonReentrant {
        if (matchId >= _matchCount) revert MatchNotFound(matchId);
        Match storage m = matches[matchId];

        if (m.state != MatchState.Created)         revert WrongState(m.state);
        if (msg.sender != m.player1)               revert NotPlayer1();
        if (block.timestamp <= m.joinDeadline)     revert DeadlineNotPassed();

        // Effects before any interaction.
        m.state = MatchState.Cancelled;
        pendingWithdrawals[m.player1] += m.stake;

        emit MatchCancelled(matchId);
    }

    /// @notice Pull accumulated winnings or refund.
    ///         Uses checks-effects-interactions: balance zeroed before transfer.
    function withdraw() external nonReentrant {
        uint256 amount = pendingWithdrawals[msg.sender];
        if (amount == 0) revert NoFundsToWithdraw();

        // Zero before the external call — reentrancy guard is a second defence.
        pendingWithdrawals[msg.sender] = 0;

        (bool ok,) = msg.sender.call{value: amount}("");
        require(ok, "ETH transfer failed");

        emit Withdrawn(msg.sender, amount);
    }

    // ── View helpers ──────────────────────────────────────────────────────────

    function getMatch(uint256 matchId) external view returns (Match memory) {
        return matches[matchId];
    }

    /// @notice Off-chain helper: compute the commitment hash a player should submit.
    function commitHash(Move move, bytes32 salt, address player)
        external
        pure
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(move, salt, player));
    }

    function matchCount() external view returns (uint256) {
        return _matchCount;
    }

    // ── Internal ─────────────────────────────────────────────────────────────

    /// @dev Called when both players have revealed. Determines the winner and
    ///      credits pendingWithdrawals. No external calls here.
    function _settle(uint256 matchId, Match storage m) private {
        m.state = MatchState.Resolved;

        address w = _winner(m.move1, m.move2, m.player1, m.player2);

        if (w == address(0)) {
            // Tie: each player recovers their own stake.
            pendingWithdrawals[m.player1] += m.stake;
            pendingWithdrawals[m.player2] += m.stake;
        } else {
            // Winner collects both stakes.
            pendingWithdrawals[w] += 2 * m.stake;
        }

        emit MatchResolved(matchId, w, m.move1, m.move2);
    }

    /// @dev Rock beats Scissors, Scissors beats Paper, Paper beats Rock.
    ///      Returns address(0) for a tie.
    function _winner(Move m1, Move m2, address p1, address p2)
        private
        pure
        returns (address)
    {
        if (m1 == m2) return address(0);
        if (
            (m1 == Move.Rock     && m2 == Move.Scissors) ||
            (m1 == Move.Scissors && m2 == Move.Paper)    ||
            (m1 == Move.Paper    && m2 == Move.Rock)
        ) return p1;
        return p2;
    }
}

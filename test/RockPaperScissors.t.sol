// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {CommonBase} from "forge-std/Base.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";

import {RockPaperScissors as RPS} from "../src/RockPaperScissors.sol";

// ─────────────────────────────────────────────────────────────────────────────
// Shared helper: commitment hash and named actors
// ─────────────────────────────────────────────────────────────────────────────
contract RPSBase is Test {
    RPS internal rps;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");

    uint256 internal constant STAKE = 1 ether;

    function setUp() public virtual {
        rps = new RPS();
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(carol, 100 ether);
    }

    // ── Commitment helpers ────────────────────────────────────────────────────

    function _commit(RPS.Move move, bytes32 salt, address player) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(move, salt, player));
    }

    // ── Scenario shortcuts ────────────────────────────────────────────────────

    /// Creates a match as Alice with default STAKE.  Returns matchId.
    function _aliceCreates(bytes32 salt, RPS.Move move) internal returns (uint256 matchId) {
        vm.prank(alice);
        matchId = rps.createMatch{value: STAKE}(_commit(move, salt, alice));
    }

    /// Bob joins the match Alice created.
    function _bobJoins(uint256 matchId, bytes32 salt, RPS.Move move) internal {
        vm.prank(bob);
        rps.joinMatch{value: STAKE}(matchId, _commit(move, salt, bob));
    }

    /// Both players reveal.
    function _reveal(uint256 matchId, RPS.Move aliceMove, bytes32 aliceSalt, RPS.Move bobMove, bytes32 bobSalt)
        internal
    {
        vm.prank(alice);
        rps.reveal(matchId, aliceMove, aliceSalt);
        vm.prank(bob);
        rps.reveal(matchId, bobMove, bobSalt);
    }

    /// Full happy-path: create → join → both reveal.  Returns matchId.
    function _fullMatch(RPS.Move aliceMove, bytes32 aliceSalt, RPS.Move bobMove, bytes32 bobSalt)
        internal
        returns (uint256 matchId)
    {
        matchId = _aliceCreates(aliceSalt, aliceMove);
        _bobJoins(matchId, bobSalt, bobMove);
        _reveal(matchId, aliceMove, aliceSalt, bobMove, bobSalt);
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Unit tests
// ─────────────────────────────────────────────────────────────────────────────
contract RPS_CreateMatch_Test is RPSBase {
    // ── happy path ────────────────────────────────────────────────────────────

    function test_CreateMatch_StoresCorrectData() public {
        bytes32 salt = "aliceSalt";
        bytes32 commitment = _commit(RPS.Move.Rock, salt, alice);

        vm.prank(alice);
        uint256 id = rps.createMatch{value: STAKE}(commitment);

        assertEq(id, 0, "first matchId should be 0");

        RPS.Match memory m = rps.getMatch(id);
        assertEq(m.player1, alice);
        assertEq(m.player2, address(0));
        assertEq(m.stake, STAKE);
        assertEq(m.commitment1, commitment);
        assertEq(uint8(m.state), uint8(RPS.MatchState.Created));
        assertEq(m.joinDeadline, block.timestamp + rps.JOIN_TIMEOUT());
        assertEq(m.revealDeadline, 0);
    }

    function test_CreateMatch_EmitsEvent() public {
        bytes32 commitment = _commit(RPS.Move.Rock, "s", alice);
        vm.expectEmit(true, true, false, true);
        emit RPS.MatchCreated(0, alice, STAKE, block.timestamp + rps.JOIN_TIMEOUT());
        vm.prank(alice);
        rps.createMatch{value: STAKE}(commitment);
    }

    function test_CreateMatch_IncrementsMatchCount() public {
        vm.prank(alice);
        rps.createMatch{value: STAKE}(_commit(RPS.Move.Rock, "s", alice));
        assertEq(rps.matchCount(), 1);
        vm.prank(bob);
        rps.createMatch{value: STAKE}(_commit(RPS.Move.Paper, "t", bob));
        assertEq(rps.matchCount(), 2);
    }

    function test_CreateMatch_ContractReceivesETH() public {
        vm.prank(alice);
        rps.createMatch{value: STAKE}(_commit(RPS.Move.Rock, "s", alice));
        assertEq(address(rps).balance, STAKE);
    }

    // ── reverts ───────────────────────────────────────────────────────────────

    function test_CreateMatch_ZeroStake_Reverts() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(RPS.WrongStake.selector, 0, 1));
        rps.createMatch{value: 0}(_commit(RPS.Move.Rock, "s", alice));
    }

    function test_CreateMatch_ZeroCommitment_Reverts() public {
        vm.prank(alice);
        vm.expectRevert(RPS.ZeroCommitment.selector);
        rps.createMatch{value: STAKE}(bytes32(0));
    }
}

contract RPS_JoinMatch_Test is RPSBase {
    uint256 internal matchId;
    bytes32 internal aliceSalt = "aliceSalt";

    function setUp() public override {
        super.setUp();
        matchId = _aliceCreates(aliceSalt, RPS.Move.Rock);
    }

    // ── happy path ────────────────────────────────────────────────────────────

    function test_JoinMatch_StoresPlayer2() public {
        bytes32 bobCommit = _commit(RPS.Move.Scissors, "bobSalt", bob);
        vm.prank(bob);
        rps.joinMatch{value: STAKE}(matchId, bobCommit);

        RPS.Match memory m = rps.getMatch(matchId);
        assertEq(m.player2, bob);
        assertEq(m.commitment2, bobCommit);
        assertEq(uint8(m.state), uint8(RPS.MatchState.Active));
        assertEq(m.revealDeadline, block.timestamp + rps.REVEAL_TIMEOUT());
    }

    function test_JoinMatch_EmitsEvent() public {
        uint256 expectedDeadline = block.timestamp + rps.REVEAL_TIMEOUT();
        vm.expectEmit(true, true, false, true);
        emit RPS.PlayerJoined(matchId, bob, expectedDeadline);
        vm.prank(bob);
        rps.joinMatch{value: STAKE}(matchId, _commit(RPS.Move.Scissors, "bs", bob));
    }

    function test_JoinMatch_ContractHoldsBothStakes() public {
        vm.prank(bob);
        rps.joinMatch{value: STAKE}(matchId, _commit(RPS.Move.Scissors, "bs", bob));
        assertEq(address(rps).balance, 2 * STAKE);
    }

    // ── reverts ───────────────────────────────────────────────────────────────

    function test_JoinMatch_WrongState_Reverts() public {
        // Join once successfully
        vm.prank(bob);
        rps.joinMatch{value: STAKE}(matchId, _commit(RPS.Move.Rock, "bs", bob));
        // Try to join again
        vm.prank(carol);
        vm.expectRevert(abi.encodeWithSelector(RPS.WrongState.selector, RPS.MatchState.Active));
        rps.joinMatch{value: STAKE}(matchId, _commit(RPS.Move.Rock, "cs", carol));
    }

    function test_JoinMatch_WrongStake_Reverts() public {
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(RPS.WrongStake.selector, STAKE + 1, STAKE));
        rps.joinMatch{value: STAKE + 1}(matchId, _commit(RPS.Move.Rock, "bs", bob));
    }

    function test_JoinMatch_ZeroStake_Reverts() public {
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(RPS.WrongStake.selector, 0, STAKE));
        rps.joinMatch{value: 0}(matchId, _commit(RPS.Move.Rock, "bs", bob));
    }

    function test_JoinMatch_SelfPlay_Reverts() public {
        vm.prank(alice);
        vm.expectRevert(RPS.SelfPlay.selector);
        rps.joinMatch{value: STAKE}(matchId, _commit(RPS.Move.Rock, "as2", alice));
    }

    function test_JoinMatch_AfterDeadline_Reverts() public {
        vm.warp(block.timestamp + rps.JOIN_TIMEOUT() + 1);
        vm.prank(bob);
        vm.expectRevert(RPS.DeadlinePassed.selector);
        rps.joinMatch{value: STAKE}(matchId, _commit(RPS.Move.Rock, "bs", bob));
    }

    function test_JoinMatch_ZeroCommitment_Reverts() public {
        vm.prank(bob);
        vm.expectRevert(RPS.ZeroCommitment.selector);
        rps.joinMatch{value: STAKE}(matchId, bytes32(0));
    }

    function test_JoinMatch_NonExistentMatch_Reverts() public {
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(RPS.MatchNotFound.selector, 999));
        rps.joinMatch{value: STAKE}(999, _commit(RPS.Move.Rock, "bs", bob));
    }
}

contract RPS_Reveal_Test is RPSBase {
    bytes32 internal aliceSalt = "aliceSalt";
    bytes32 internal bobSalt = "bobSalt";
    uint256 internal matchId;

    function setUp() public override {
        super.setUp();
        matchId = _aliceCreates(aliceSalt, RPS.Move.Rock);
        _bobJoins(matchId, bobSalt, RPS.Move.Scissors);
    }

    // ── all RPS outcomes ──────────────────────────────────────────────────────

    function _runOutcome(
        RPS.Move aliceMove,
        RPS.Move bobMove,
        address expectedWinner // address(0) for tie
    )
        internal
    {
        // Each outcome needs a fresh contract.
        setUp();
        matchId = _aliceCreates(aliceSalt, aliceMove);
        _bobJoins(matchId, bobSalt, bobMove);

        // Reveal in two steps so we can place the expectEmit for MatchResolved
        // immediately before the call that actually emits it (bob's reveal is
        // the settling call because _reveal calls alice first).
        vm.prank(alice);
        rps.reveal(matchId, aliceMove, aliceSalt);

        // MatchResolved is emitted by the second (settling) reveal.
        vm.expectEmit(true, true, false, true);
        emit RPS.MatchResolved(matchId, expectedWinner, aliceMove, bobMove);
        vm.prank(bob);
        rps.reveal(matchId, bobMove, bobSalt);

        RPS.Match memory m = rps.getMatch(matchId);
        assertEq(uint8(m.state), uint8(RPS.MatchState.Resolved));

        if (expectedWinner == address(0)) {
            // Tie: both recover their own stake
            assertEq(rps.pendingWithdrawals(alice), STAKE);
            assertEq(rps.pendingWithdrawals(bob), STAKE);
        } else if (expectedWinner == alice) {
            assertEq(rps.pendingWithdrawals(alice), 2 * STAKE);
            assertEq(rps.pendingWithdrawals(bob), 0);
        } else {
            assertEq(rps.pendingWithdrawals(bob), 2 * STAKE);
            assertEq(rps.pendingWithdrawals(alice), 0);
        }
    }

    // P1 wins (3 cases)
    function test_Reveal_RockBeatsScissors_P1Wins() public {
        _runOutcome(RPS.Move.Rock, RPS.Move.Scissors, alice);
    }

    function test_Reveal_ScissorsBeatsPaper_P1Wins() public {
        _runOutcome(RPS.Move.Scissors, RPS.Move.Paper, alice);
    }

    function test_Reveal_PaperBeatsRock_P1Wins() public {
        _runOutcome(RPS.Move.Paper, RPS.Move.Rock, alice);
    }

    // P2 wins (3 cases)
    function test_Reveal_ScissorsBeatRock_P2Wins() public {
        _runOutcome(RPS.Move.Rock, RPS.Move.Paper, bob);
    }

    function test_Reveal_PaperBeatsScissors_P2Wins() public {
        _runOutcome(RPS.Move.Scissors, RPS.Move.Rock, bob);
    }

    function test_Reveal_RockBeatsScissors_P2Wins() public {
        _runOutcome(RPS.Move.Paper, RPS.Move.Scissors, bob);
    }

    // Ties (3 cases)
    function test_Reveal_RockRock_Tie() public {
        _runOutcome(RPS.Move.Rock, RPS.Move.Rock, address(0));
    }

    function test_Reveal_PaperPaper_Tie() public {
        _runOutcome(RPS.Move.Paper, RPS.Move.Paper, address(0));
    }

    function test_Reveal_ScissorsScissors_Tie() public {
        _runOutcome(RPS.Move.Scissors, RPS.Move.Scissors, address(0));
    }

    // ── state transitions ─────────────────────────────────────────────────────

    function test_Reveal_FirstReveal_MovesToRevealingState() public {
        vm.prank(alice);
        rps.reveal(matchId, RPS.Move.Rock, aliceSalt);
        assertEq(uint8(rps.getMatch(matchId).state), uint8(RPS.MatchState.Revealing));
    }

    function test_Reveal_SecondReveal_MovesToResolvedState() public {
        vm.prank(alice);
        rps.reveal(matchId, RPS.Move.Rock, aliceSalt);
        vm.prank(bob);
        rps.reveal(matchId, RPS.Move.Scissors, bobSalt);
        assertEq(uint8(rps.getMatch(matchId).state), uint8(RPS.MatchState.Resolved));
    }

    function test_Reveal_EmitsMoveRevealedEvent() public {
        vm.expectEmit(true, true, false, false);
        emit RPS.MoveRevealed(matchId, alice);
        vm.prank(alice);
        rps.reveal(matchId, RPS.Move.Rock, aliceSalt);
    }

    // ── order independence ────────────────────────────────────────────────────

    function test_Reveal_BobCanRevealFirst() public {
        vm.prank(bob);
        rps.reveal(matchId, RPS.Move.Scissors, bobSalt);
        assertEq(uint8(rps.getMatch(matchId).state), uint8(RPS.MatchState.Revealing));

        vm.prank(alice);
        rps.reveal(matchId, RPS.Move.Rock, aliceSalt);
        assertEq(uint8(rps.getMatch(matchId).state), uint8(RPS.MatchState.Resolved));
        assertEq(rps.pendingWithdrawals(alice), 2 * STAKE);
    }

    // ── reverts ───────────────────────────────────────────────────────────────

    function test_Reveal_WrongMove_Reverts() public {
        vm.prank(alice);
        vm.expectRevert(RPS.CommitMismatch.selector);
        rps.reveal(matchId, RPS.Move.Paper, aliceSalt); // committed Rock
    }

    function test_Reveal_WrongSalt_Reverts() public {
        vm.prank(alice);
        vm.expectRevert(RPS.CommitMismatch.selector);
        rps.reveal(matchId, RPS.Move.Rock, "wrongSalt");
    }

    function test_Reveal_NoneMove_Reverts() public {
        vm.prank(alice);
        vm.expectRevert(RPS.InvalidMove.selector);
        rps.reveal(matchId, RPS.Move.None, aliceSalt);
    }

    function test_Reveal_AfterDeadline_Reverts() public {
        vm.warp(block.timestamp + rps.REVEAL_TIMEOUT() + 1);
        vm.prank(alice);
        vm.expectRevert(RPS.DeadlinePassed.selector);
        rps.reveal(matchId, RPS.Move.Rock, aliceSalt);
    }

    function test_Reveal_DoubleReveal_Reverts() public {
        vm.prank(alice);
        rps.reveal(matchId, RPS.Move.Rock, aliceSalt);
        vm.prank(alice);
        vm.expectRevert(RPS.AlreadyRevealed.selector);
        rps.reveal(matchId, RPS.Move.Rock, aliceSalt);
    }

    function test_Reveal_NonParticipant_Reverts() public {
        vm.prank(carol);
        vm.expectRevert(RPS.NotParticipant.selector);
        rps.reveal(matchId, RPS.Move.Rock, aliceSalt);
    }

    function test_Reveal_WrongState_Created_Reverts() public {
        // A new match that hasn't been joined yet
        uint256 newId = _aliceCreates("salt2", RPS.Move.Rock);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(RPS.WrongState.selector, RPS.MatchState.Created));
        rps.reveal(newId, RPS.Move.Rock, "salt2");
    }

    function test_Reveal_NonExistentMatch_Reverts() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(RPS.MatchNotFound.selector, 999));
        rps.reveal(999, RPS.Move.Rock, aliceSalt);
    }
}

contract RPS_Cancel_Test is RPSBase {
    uint256 internal matchId;
    bytes32 internal aliceSalt = "aliceSalt";

    function setUp() public override {
        super.setUp();
        matchId = _aliceCreates(aliceSalt, RPS.Move.Rock);
    }

    function test_Cancel_AfterTimeout_RefundsPlayer1() public {
        vm.warp(block.timestamp + rps.JOIN_TIMEOUT() + 1);

        uint256 before = alice.balance;
        vm.prank(alice);
        rps.cancelMatch(matchId);

        assertEq(uint8(rps.getMatch(matchId).state), uint8(RPS.MatchState.Cancelled));
        assertEq(rps.pendingWithdrawals(alice), STAKE);

        // Withdraw and verify
        vm.prank(alice);
        rps.withdraw();
        assertEq(alice.balance, before + STAKE);
    }

    function test_Cancel_EmitsCancelledEvent() public {
        vm.warp(block.timestamp + rps.JOIN_TIMEOUT() + 1);
        vm.expectEmit(true, false, false, false);
        emit RPS.MatchCancelled(matchId);
        vm.prank(alice);
        rps.cancelMatch(matchId);
    }

    function test_Cancel_BeforeDeadline_Reverts() public {
        vm.prank(alice);
        vm.expectRevert(RPS.DeadlineNotPassed.selector);
        rps.cancelMatch(matchId);
    }

    function test_Cancel_WrongCaller_Reverts() public {
        vm.warp(block.timestamp + rps.JOIN_TIMEOUT() + 1);
        vm.prank(bob);
        vm.expectRevert(RPS.NotPlayer1.selector);
        rps.cancelMatch(matchId);
    }

    function test_Cancel_WrongState_Active_Reverts() public {
        _bobJoins(matchId, "bobSalt", RPS.Move.Scissors);
        vm.warp(block.timestamp + rps.JOIN_TIMEOUT() + 1);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(RPS.WrongState.selector, RPS.MatchState.Active));
        rps.cancelMatch(matchId);
    }

    function test_Cancel_ExactlyAtDeadline_Reverts() public {
        // At exactly joinDeadline, the deadline has NOT passed
        vm.warp(rps.getMatch(matchId).joinDeadline);
        vm.prank(alice);
        vm.expectRevert(RPS.DeadlineNotPassed.selector);
        rps.cancelMatch(matchId);
    }

    function test_Cancel_OneSecondAfterDeadline_Succeeds() public {
        vm.warp(rps.getMatch(matchId).joinDeadline + 1);
        vm.prank(alice);
        rps.cancelMatch(matchId);
        assertEq(uint8(rps.getMatch(matchId).state), uint8(RPS.MatchState.Cancelled));
    }
}

contract RPS_ResolveExpired_Test is RPSBase {
    bytes32 internal aliceSalt = "aliceSalt";
    bytes32 internal bobSalt = "bobSalt";
    uint256 internal matchId;

    function setUp() public override {
        super.setUp();
        matchId = _aliceCreates(aliceSalt, RPS.Move.Rock);
        _bobJoins(matchId, bobSalt, RPS.Move.Scissors);
    }

    // ── one revealed ──────────────────────────────────────────────────────────

    function test_ResolveExpired_P1Revealed_P1Wins() public {
        vm.prank(alice);
        rps.reveal(matchId, RPS.Move.Rock, aliceSalt);

        vm.warp(rps.getMatch(matchId).revealDeadline + 1);

        vm.expectEmit(true, true, false, true);
        emit RPS.MatchResolved(matchId, alice, RPS.Move.Rock, RPS.Move.None);

        rps.resolveExpired(matchId); // anyone can call

        assertEq(uint8(rps.getMatch(matchId).state), uint8(RPS.MatchState.Resolved));
        assertEq(rps.pendingWithdrawals(alice), 2 * STAKE);
        assertEq(rps.pendingWithdrawals(bob), 0);
    }

    function test_ResolveExpired_P2Revealed_P2Wins() public {
        vm.prank(bob);
        rps.reveal(matchId, RPS.Move.Scissors, bobSalt);

        vm.warp(rps.getMatch(matchId).revealDeadline + 1);

        emit RPS.MatchResolved(matchId, bob, RPS.Move.None, RPS.Move.Scissors);
        rps.resolveExpired(matchId);

        assertEq(rps.pendingWithdrawals(bob), 2 * STAKE);
        assertEq(rps.pendingWithdrawals(alice), 0);
    }

    // ── neither revealed ──────────────────────────────────────────────────────

    function test_ResolveExpired_NeitherRevealed_BothRefunded() public {
        vm.warp(rps.getMatch(matchId).revealDeadline + 1);

        vm.expectEmit(true, false, false, false);
        emit RPS.MatchCancelled(matchId);

        rps.resolveExpired(matchId);

        assertEq(uint8(rps.getMatch(matchId).state), uint8(RPS.MatchState.Cancelled));
        assertEq(rps.pendingWithdrawals(alice), STAKE);
        assertEq(rps.pendingWithdrawals(bob), STAKE);
    }

    function test_ResolveExpired_NeitherRevealed_BothCanWithdraw() public {
        vm.warp(rps.getMatch(matchId).revealDeadline + 1);
        rps.resolveExpired(matchId);

        uint256 aliceBefore = alice.balance;
        uint256 bobBefore = bob.balance;

        vm.prank(alice);
        rps.withdraw();
        vm.prank(bob);
        rps.withdraw();

        assertEq(alice.balance, aliceBefore + STAKE);
        assertEq(bob.balance, bobBefore + STAKE);
    }

    // ── callable by anyone ────────────────────────────────────────────────────

    function test_ResolveExpired_CalledByCarol_Works() public {
        vm.prank(alice);
        rps.reveal(matchId, RPS.Move.Rock, aliceSalt);
        vm.warp(rps.getMatch(matchId).revealDeadline + 1);

        vm.prank(carol); // third party settles
        rps.resolveExpired(matchId);

        assertEq(rps.pendingWithdrawals(alice), 2 * STAKE);
    }

    // ── reverts ───────────────────────────────────────────────────────────────

    function test_ResolveExpired_BeforeDeadline_Reverts() public {
        vm.prank(alice);
        rps.reveal(matchId, RPS.Move.Rock, aliceSalt);
        vm.expectRevert(RPS.DeadlineNotPassed.selector);
        rps.resolveExpired(matchId);
    }

    function test_ResolveExpired_AlreadyResolved_Reverts() public {
        _reveal(matchId, RPS.Move.Rock, aliceSalt, RPS.Move.Scissors, bobSalt);
        vm.warp(rps.getMatch(matchId).revealDeadline + 1);
        vm.expectRevert(abi.encodeWithSelector(RPS.WrongState.selector, RPS.MatchState.Resolved));
        rps.resolveExpired(matchId);
    }

    function test_ResolveExpired_WrongState_Created_Reverts() public {
        uint256 newId = _aliceCreates("s2", RPS.Move.Rock);
        vm.warp(block.timestamp + rps.REVEAL_TIMEOUT() + 1);
        vm.expectRevert(abi.encodeWithSelector(RPS.WrongState.selector, RPS.MatchState.Created));
        rps.resolveExpired(newId);
    }

    function test_ResolveExpired_ExactlyAtDeadline_Reverts() public {
        vm.warp(rps.getMatch(matchId).revealDeadline);
        vm.expectRevert(RPS.DeadlineNotPassed.selector);
        rps.resolveExpired(matchId);
    }

    function test_ResolveExpired_DoubleCall_Reverts() public {
        vm.warp(rps.getMatch(matchId).revealDeadline + 1);
        rps.resolveExpired(matchId);
        vm.expectRevert(abi.encodeWithSelector(RPS.WrongState.selector, RPS.MatchState.Cancelled));
        rps.resolveExpired(matchId);
    }
}

contract RPS_Withdraw_Test is RPSBase {
    bytes32 internal aliceSalt = "aliceSalt";
    bytes32 internal bobSalt = "bobSalt";

    function test_Withdraw_WinnerReceivesFullPot() public {
        uint256 id = _fullMatch(RPS.Move.Rock, aliceSalt, RPS.Move.Scissors, bobSalt);
        assertEq(uint8(rps.getMatch(id).state), uint8(RPS.MatchState.Resolved));

        uint256 before = alice.balance;
        vm.prank(alice);
        rps.withdraw();

        assertEq(alice.balance, before + 2 * STAKE);
        assertEq(rps.pendingWithdrawals(alice), 0);
        assertEq(address(rps).balance, 0);
    }

    function test_Withdraw_TieBothReceiveStakeBack() public {
        _fullMatch(RPS.Move.Rock, aliceSalt, RPS.Move.Rock, bobSalt);

        uint256 aliceBefore = alice.balance;
        uint256 bobBefore = bob.balance;

        vm.prank(alice);
        rps.withdraw();
        vm.prank(bob);
        rps.withdraw();

        assertEq(alice.balance, aliceBefore + STAKE);
        assertEq(bob.balance, bobBefore + STAKE);
        assertEq(address(rps).balance, 0);
    }

    function test_Withdraw_EmitsEvent() public {
        _fullMatch(RPS.Move.Rock, aliceSalt, RPS.Move.Scissors, bobSalt);
        vm.expectEmit(true, false, false, true);
        emit RPS.Withdrawn(alice, 2 * STAKE);
        vm.prank(alice);
        rps.withdraw();
    }

    function test_Withdraw_ZeroBalance_Reverts() public {
        vm.prank(alice);
        vm.expectRevert(RPS.NoFundsToWithdraw.selector);
        rps.withdraw();
    }

    function test_Withdraw_DoubleWithdraw_Reverts() public {
        _fullMatch(RPS.Move.Rock, aliceSalt, RPS.Move.Scissors, bobSalt);
        vm.prank(alice);
        rps.withdraw();
        vm.prank(alice);
        vm.expectRevert(RPS.NoFundsToWithdraw.selector);
        rps.withdraw();
    }

    function test_Withdraw_ContractBalanceDecreasesCorrectly() public {
        _fullMatch(RPS.Move.Rock, aliceSalt, RPS.Move.Scissors, bobSalt);
        assertEq(address(rps).balance, 2 * STAKE);
        vm.prank(alice);
        rps.withdraw();
        assertEq(address(rps).balance, 0);
    }

    /// A reentrant receiver must not be able to double-withdraw.
    function test_Withdraw_Reentrancy_Blocked() public {
        ReentrantWithdrawer attacker = new ReentrantWithdrawer(rps);
        vm.deal(address(attacker), 100 ether);

        // Attacker creates a match against bob (Alice's role here)
        bytes32 attackerSalt = "attackerSalt";
        vm.prank(address(attacker));
        uint256 id = rps.createMatch{value: STAKE}(_commit(RPS.Move.Rock, attackerSalt, address(attacker)));

        // bob joins
        vm.prank(bob);
        rps.joinMatch{value: STAKE}(id, _commit(RPS.Move.Scissors, bobSalt, bob));

        // Both reveal: attacker wins
        attacker.reveal(id, RPS.Move.Rock, attackerSalt);
        vm.prank(bob);
        rps.reveal(id, RPS.Move.Scissors, bobSalt);

        // Should only pay out once despite reentrancy attempt
        attacker.tryReentrantWithdraw();

        // Contract balance should be exactly zero
        assertEq(address(rps).balance, 0);
        assertEq(address(attacker).balance, 100 ether - STAKE + 2 * STAKE);
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reentrancy helper
// ─────────────────────────────────────────────────────────────────────────────
contract ReentrantWithdrawer {
    RPS private rps;
    bool private _attacking;
    uint256 private _count;

    constructor(RPS _rps) {
        rps = _rps;
    }

    function reveal(uint256 matchId, RPS.Move move, bytes32 salt) external {
        rps.reveal(matchId, move, salt);
    }

    function tryReentrantWithdraw() external {
        _attacking = true;
        rps.withdraw();
    }

    receive() external payable {
        if (_attacking && _count < 3) {
            _count++;
            try rps.withdraw() {} catch {} // should revert each time
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Fuzz tests
// ─────────────────────────────────────────────────────────────────────────────
contract RPS_Fuzz_Test is RPSBase {
    // All valid move combinations: verify winner determination is correct
    function testFuzz_WinnerIsCorrect(uint8 m1Seed, uint8 m2Seed) public {
        // Map seeds to valid moves (1-3)
        RPS.Move m1 = RPS.Move(bound(m1Seed, 1, 3));
        RPS.Move m2 = RPS.Move(bound(m2Seed, 1, 3));

        bytes32 s1 = keccak256(abi.encodePacked("salt1", m1Seed));
        bytes32 s2 = keccak256(abi.encodePacked("salt2", m2Seed));

        _fullMatch(m1, s1, m2, s2);

        uint256 alicePending = rps.pendingWithdrawals(alice);
        uint256 bobPending = rps.pendingWithdrawals(bob);

        if (m1 == m2) {
            // Tie
            assertEq(alicePending, STAKE);
            assertEq(bobPending, STAKE);
        } else if (
            (m1 == RPS.Move.Rock && m2 == RPS.Move.Scissors) || (m1 == RPS.Move.Scissors && m2 == RPS.Move.Paper)
                || (m1 == RPS.Move.Paper && m2 == RPS.Move.Rock)
        ) {
            // Alice wins
            assertEq(alicePending, 2 * STAKE);
            assertEq(bobPending, 0);
        } else {
            // Bob wins
            assertEq(bobPending, 2 * STAKE);
            assertEq(alicePending, 0);
        }

        // Total pending always equals total staked
        assertEq(alicePending + bobPending, 2 * STAKE);
    }

    // Wrong salt always fails commitment verification
    function testFuzz_WrongSalt_AlwaysReverts(bytes32 correctSalt, bytes32 wrongSalt) public {
        vm.assume(wrongSalt != correctSalt);

        uint256 id = _aliceCreates(correctSalt, RPS.Move.Rock);
        _bobJoins(id, "bSalt", RPS.Move.Scissors);

        vm.prank(alice);
        vm.expectRevert(RPS.CommitMismatch.selector);
        rps.reveal(id, RPS.Move.Rock, wrongSalt);
    }

    // Wrong move always fails commitment verification
    function testFuzz_WrongMove_AlwaysReverts(uint8 wrongMoveSeed) public {
        bytes32 salt = "aliceSalt";
        uint256 id = _aliceCreates(salt, RPS.Move.Rock);
        _bobJoins(id, "bSalt", RPS.Move.Scissors);

        // Any move other than Rock should fail
        RPS.Move wrongMove = RPS.Move(bound(wrongMoveSeed, 1, 3));
        vm.assume(wrongMove != RPS.Move.Rock);

        vm.prank(alice);
        vm.expectRevert(RPS.CommitMismatch.selector);
        rps.reveal(id, wrongMove, salt);
    }

    // Stake amounts: any nonzero amount works; both players must match exactly
    function testFuzz_StakeAmount_MustMatch(uint256 stake) public {
        stake = bound(stake, 1, 100 ether);
        vm.deal(alice, stake * 2);
        vm.deal(bob, stake * 2);

        bytes32 s1 = "s1";
        bytes32 s2 = "s2";

        vm.prank(alice);
        uint256 id = rps.createMatch{value: stake}(_commit(RPS.Move.Rock, s1, alice));

        // Sending stake ± 1 should fail
        if (stake > 1) {
            vm.prank(bob);
            vm.expectRevert(abi.encodeWithSelector(RPS.WrongStake.selector, stake - 1, stake));
            rps.joinMatch{value: stake - 1}(id, _commit(RPS.Move.Scissors, s2, bob));
        }

        vm.prank(bob);
        rps.joinMatch{value: stake}(id, _commit(RPS.Move.Scissors, s2, bob));
        assertEq(rps.getMatch(id).stake, stake);
        assertEq(address(rps).balance, 2 * stake);
    }

    // Commitment includes sender address: commitment computed for alice cannot
    // be used by bob to reveal, even with the same move and salt.
    function testFuzz_CommitmentBindsToAddress(bytes32 salt, uint8 moveSeed) public {
        RPS.Move move = RPS.Move(bound(moveSeed, 1, 3));

        // Bob's fixed commitment values — independent of fuzz inputs.
        bytes32 BOB_SALT = bytes32(uint256(0xdeadbeef));
        RPS.Move BOB_MOVE = RPS.Move.Paper;

        // Skip the degenerate case where (move, salt) == (BOB_MOVE, BOB_SALT):
        // bob's commit-reveal would legitimately succeed with those values,
        // so the expectRevert below would be wrong.
        vm.assume(!(move == BOB_MOVE && salt == BOB_SALT));

        uint256 id = _aliceCreates(salt, move);
        _bobJoins(id, BOB_SALT, BOB_MOVE);

        // Bob tries to reveal using alice's (move, salt).
        // keccak256(move, salt, bob) != commitment1 (alice's address differs)
        // keccak256(move, salt, bob) != commitment2 (BOB_MOVE/BOB_SALT assumed ≠ move/salt)
        vm.prank(bob);
        vm.expectRevert(RPS.CommitMismatch.selector);
        rps.reveal(id, move, salt);
    }

    // Multiple concurrent matches: balances remain independent
    function testFuzz_MultipleMatches_BalancesIndependent(uint8 m1Seed, uint8 m2Seed) public {
        RPS.Move m1 = RPS.Move(bound(m1Seed, 1, 3));
        RPS.Move m2 = RPS.Move(bound(m2Seed, 1, 3));

        bytes32 s1a = "s1a";
        bytes32 s1b = "s1b";
        bytes32 s2a = "s2a";
        bytes32 s2b = "s2b";

        // Two parallel matches
        uint256 idA = _aliceCreates(s1a, m1);
        vm.prank(bob);
        rps.joinMatch{value: STAKE}(idA, _commit(m2, s1b, bob));

        // Alice also creates a second match (as carol and bob)
        vm.prank(carol);
        uint256 idB = rps.createMatch{value: STAKE}(_commit(m1, s2a, carol));
        vm.prank(alice);
        rps.joinMatch{value: STAKE}(idB, _commit(m2, s2b, alice));

        // Contract holds 4 stakes
        assertEq(address(rps).balance, 4 * STAKE);

        // Reveal match A
        _reveal(idA, m1, s1a, m2, s1b);

        // Reveal match B
        vm.prank(carol);
        rps.reveal(idB, m1, s2a);
        vm.prank(alice);
        rps.reveal(idB, m2, s2b);

        // All stakes accounted for
        uint256 total = rps.pendingWithdrawals(alice) + rps.pendingWithdrawals(bob) + rps.pendingWithdrawals(carol);
        assertEq(total, 4 * STAKE);
        assertEq(address(rps).balance, 4 * STAKE); // still in contract until withdrawn
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Invariant testing
// ─────────────────────────────────────────────────────────────────────────────

/// @dev Handler drives random sequences of RPS actions.
///      Ghost variables let the invariant contract check conservation of ETH.
contract RPS_Handler is CommonBase, StdCheats, StdUtils {
    RPS public rps;

    // Persistent actors
    address[] public actors;

    // Track match meta-data the contract doesn't expose directly
    struct MatchInfo {
        address p1;
        address p2;
        RPS.Move move1;
        RPS.Move move2;
        bytes32 salt1;
        bytes32 salt2;
        bool joined;
    }
    mapping(uint256 => MatchInfo) public info;
    uint256[] public matchIds;

    // Ghost: track all ETH that entered and left the contract
    uint256 public ghost_deposited;
    uint256 public ghost_withdrawn;

    constructor(RPS _rps) {
        rps = _rps;
        actors.push(makeAddr("h_alice"));
        actors.push(makeAddr("h_bob"));
        actors.push(makeAddr("h_carol"));
        actors.push(makeAddr("h_dave"));
        for (uint256 i; i < actors.length; i++) {
            vm.deal(actors[i], 1000 ether);
        }
    }

    // ── Actions ───────────────────────────────────────────────────────────────

    function createMatch(uint256 actorSeed, uint256 stakeSeed, uint8 moveSeed, uint256 saltSeed) external {
        address actor = actors[actorSeed % actors.length];
        uint256 stake = bound(stakeSeed, 0.001 ether, 10 ether);
        RPS.Move move = RPS.Move(bound(moveSeed, 1, 3));
        bytes32 salt = bytes32(saltSeed ^ uint256(uint160(actor)));

        if (actor.balance < stake) return;

        bytes32 commitment = rps.commitHash(move, salt, actor);

        vm.prank(actor);
        uint256 id = rps.createMatch{value: stake}(commitment);

        info[id] = MatchInfo(actor, address(0), move, RPS.Move.None, salt, bytes32(0), false);
        matchIds.push(id);
        ghost_deposited += stake;
    }

    function joinMatch(uint256 matchSeed, uint256 actorSeed, uint8 moveSeed, uint256 saltSeed) external {
        if (matchIds.length == 0) return;
        uint256 id = matchIds[matchSeed % matchIds.length];
        MatchInfo storage mi = info[id];
        if (mi.joined) return;

        RPS.Match memory m = rps.getMatch(id);
        if (m.state != RPS.MatchState.Created) return;
        if (block.timestamp > m.joinDeadline) return;

        // Pick an actor that isn't player1
        address actor = actors[actorSeed % actors.length];
        if (actor == mi.p1) actor = actors[(actorSeed + 1) % actors.length];
        if (actor == mi.p1) return; // all actors same as p1 (edge case)
        if (actor.balance < m.stake) return;

        RPS.Move move = RPS.Move(bound(moveSeed, 1, 3));
        bytes32 salt = bytes32(saltSeed ^ uint256(uint160(actor)));
        bytes32 commitment = rps.commitHash(move, salt, actor);

        vm.prank(actor);
        try rps.joinMatch{value: m.stake}(id, commitment) {
            mi.p2 = actor;
            mi.move2 = move;
            mi.salt2 = salt;
            mi.joined = true;
            ghost_deposited += m.stake;
        } catch {}
    }

    function reveal(uint256 matchSeed, bool p1Goes) external {
        if (matchIds.length == 0) return;
        uint256 id = matchIds[matchSeed % matchIds.length];
        MatchInfo storage mi = info[id];

        RPS.Match memory m = rps.getMatch(id);
        if (m.state != RPS.MatchState.Active && m.state != RPS.MatchState.Revealing) return;
        if (block.timestamp > m.revealDeadline) return;

        if (p1Goes && !m.revealed1) {
            vm.prank(mi.p1);
            try rps.reveal(id, mi.move1, mi.salt1) {} catch {}
        } else if (!p1Goes && !m.revealed2 && mi.p2 != address(0)) {
            vm.prank(mi.p2);
            try rps.reveal(id, mi.move2, mi.salt2) {} catch {}
        }
    }

    function resolveExpired(uint256 matchSeed) external {
        if (matchIds.length == 0) return;
        uint256 id = matchIds[matchSeed % matchIds.length];
        RPS.Match memory m = rps.getMatch(id);
        if (m.state != RPS.MatchState.Active && m.state != RPS.MatchState.Revealing) return;
        if (block.timestamp <= m.revealDeadline) return;
        try rps.resolveExpired(id) {} catch {}
    }

    function cancelMatch(uint256 matchSeed) external {
        if (matchIds.length == 0) return;
        uint256 id = matchIds[matchSeed % matchIds.length];
        MatchInfo storage mi = info[id];
        RPS.Match memory m = rps.getMatch(id);
        if (m.state != RPS.MatchState.Created) return;
        if (block.timestamp <= m.joinDeadline) return;

        vm.prank(mi.p1);
        try rps.cancelMatch(id) {} catch {}
    }

    function withdraw(uint256 actorSeed) external {
        address actor = actors[actorSeed % actors.length];
        uint256 pending = rps.pendingWithdrawals(actor);
        if (pending == 0) return;

        vm.prank(actor);
        rps.withdraw();
        ghost_withdrawn += pending;
    }

    function warpTime(uint256 deltaSeed) external {
        uint256 delta = bound(deltaSeed, 0, 48 hours);
        vm.warp(block.timestamp + delta);
    }

    // ── Helpers for invariant assertions ─────────────────────────────────────

    /// Sum of pending withdrawals for all handler actors
    function sumPendingWithdrawals() external view returns (uint256 total) {
        for (uint256 i; i < actors.length; i++) {
            total += rps.pendingWithdrawals(actors[i]);
        }
    }

    /// Sum of stakes locked in non-terminal matches
    function sumLockedStakes() external view returns (uint256 total) {
        for (uint256 i; i < matchIds.length; i++) {
            RPS.Match memory m = rps.getMatch(matchIds[i]);
            if (m.state == RPS.MatchState.Created) {
                total += m.stake;
            } else if (m.state == RPS.MatchState.Active || m.state == RPS.MatchState.Revealing) {
                total += 2 * m.stake;
            }
            // Resolved / Cancelled: stake moved to pendingWithdrawals or already withdrawn
        }
    }
}

contract RPS_Invariant_Test is StdInvariant, Test {
    RPS internal rps;
    RPS_Handler internal handler;

    function setUp() public {
        rps = new RPS();
        handler = new RPS_Handler(rps);
        targetContract(address(handler));
    }

    /// The contract's ETH balance must always equal locked stakes + pending withdrawals.
    /// This is the core conservation invariant: no ETH is created or destroyed.
    function invariant_balanceEqualsLiabilities() public view {
        uint256 locked = handler.sumLockedStakes();
        uint256 pending = handler.sumPendingWithdrawals();
        assertEq(address(rps).balance, locked + pending, "balance != locked + pending");
    }

    /// Total ETH that entered the contract equals total that left plus what remains.
    function invariant_ethConserved() public view {
        assertEq(handler.ghost_deposited(), handler.ghost_withdrawn() + address(rps).balance, "ETH not conserved");
    }

    /// No individual actor can have more pending than the total pot of any match.
    function invariant_noPendingExceedsTotalStaked() public view {
        // If any actor has pending > 0, the total ETH deposited must cover it.
        uint256 pending = handler.sumPendingWithdrawals();
        assertLe(pending, handler.ghost_deposited() - handler.ghost_withdrawn());
    }
}

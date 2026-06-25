export const RPS_ABI = [
  {
    type: 'function', name: 'createMatch',
    inputs: [{ name: 'commitment', type: 'bytes32' }],
    outputs: [{ name: 'matchId', type: 'uint256' }],
    stateMutability: 'payable',
  },
  {
    type: 'function', name: 'joinMatch',
    inputs: [{ name: 'matchId', type: 'uint256' }, { name: 'commitment', type: 'bytes32' }],
    outputs: [],
    stateMutability: 'payable',
  },
  {
    type: 'function', name: 'reveal',
    inputs: [
      { name: 'matchId', type: 'uint256' },
      { name: 'move', type: 'uint8' },
      { name: 'salt', type: 'bytes32' },
    ],
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function', name: 'cancelMatch',
    inputs: [{ name: 'matchId', type: 'uint256' }],
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function', name: 'resolveExpired',
    inputs: [{ name: 'matchId', type: 'uint256' }],
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function', name: 'withdraw',
    inputs: [],
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function', name: 'getMatch',
    inputs: [{ name: 'matchId', type: 'uint256' }],
    outputs: [
      {
        name: '', type: 'tuple',
        components: [
          { name: 'player1', type: 'address' },
          { name: 'player2', type: 'address' },
          { name: 'stake', type: 'uint256' },
          { name: 'commitment1', type: 'bytes32' },
          { name: 'commitment2', type: 'bytes32' },
          { name: 'move1', type: 'uint8' },
          { name: 'move2', type: 'uint8' },
          { name: 'revealed1', type: 'bool' },
          { name: 'revealed2', type: 'bool' },
          { name: 'state', type: 'uint8' },
          { name: 'joinDeadline', type: 'uint256' },
          { name: 'revealDeadline', type: 'uint256' },
        ],
      },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function', name: 'pendingWithdrawals',
    inputs: [{ name: '', type: 'address' }],
    outputs: [{ name: '', type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function', name: 'matchCount',
    inputs: [],
    outputs: [{ name: '', type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'event', name: 'MatchCreated',
    inputs: [
      { name: 'matchId', type: 'uint256', indexed: true },
      { name: 'player1', type: 'address', indexed: true },
      { name: 'stake', type: 'uint256', indexed: false },
      { name: 'joinDeadline', type: 'uint256', indexed: false },
    ],
  },
  {
    type: 'event', name: 'PlayerJoined',
    inputs: [
      { name: 'matchId', type: 'uint256', indexed: true },
      { name: 'player2', type: 'address', indexed: true },
      { name: 'revealDeadline', type: 'uint256', indexed: false },
    ],
  },
  {
    type: 'event', name: 'MoveRevealed',
    inputs: [
      { name: 'matchId', type: 'uint256', indexed: true },
      { name: 'player', type: 'address', indexed: true },
    ],
  },
  {
    type: 'event', name: 'MatchResolved',
    inputs: [
      { name: 'matchId', type: 'uint256', indexed: true },
      { name: 'winner', type: 'address', indexed: true },
      { name: 'move1', type: 'uint8', indexed: false },
      { name: 'move2', type: 'uint8', indexed: false },
    ],
  },
  {
    type: 'event', name: 'MatchCancelled',
    inputs: [{ name: 'matchId', type: 'uint256', indexed: true }],
  },
  {
    type: 'event', name: 'Withdrawn',
    inputs: [
      { name: 'player', type: 'address', indexed: true },
      { name: 'amount', type: 'uint256', indexed: false },
    ],
  },
] as const

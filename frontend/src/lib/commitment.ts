import { keccak256, encodePacked, type Address } from 'viem'

export function makeCommitment(move: number, salt: `0x${string}`, player: Address): `0x${string}` {
  return keccak256(encodePacked(['uint8', 'bytes32', 'address'], [move, salt, player]))
}

export function randomSalt(): `0x${string}` {
  const bytes = crypto.getRandomValues(new Uint8Array(32))
  return `0x${Array.from(bytes, b => b.toString(16).padStart(2, '0')).join('')}` as `0x${string}`
}

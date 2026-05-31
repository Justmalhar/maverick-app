/**
 * TOFU safety-number rendering. After a Noise_XX handshake the user verifies
 * out-of-band that the desktop's static key is the one they intended to pair
 * with. We render a Signal-style numeric fingerprint: SHA-256 of the static
 * key, taken as 30 decimal digits in five groups of six (easy to read aloud or
 * compare against the desktop's display).
 *
 * Also exposes a short alphanumeric fingerprint (the QR's `f` field equivalent)
 * for the compact device-list badge.
 */

import { hash } from './noise-crypto';

const GROUPS = 5;
const GROUP_DIGITS = 6;

/** 30-digit, five-group safety number derived from a static public key. */
export function safetyNumber(staticPublicKey: Uint8Array): string {
  const digest = hash(staticPublicKey);
  const groups: string[] = [];
  for (let g = 0; g < GROUPS; g++) {
    // Each group consumes 4 digest bytes → a 32-bit value → 6 decimal digits.
    const base = g * 4;
    const value =
      ((digest[base]! << 24) |
        (digest[base + 1]! << 16) |
        (digest[base + 2]! << 8) |
        digest[base + 3]!) >>>
      0;
    groups.push((value % 1_000_000).toString().padStart(GROUP_DIGITS, '0'));
  }
  return groups.join(' ');
}

/** Short uppercase hex fingerprint (first 8 hex chars of the digest). */
export function shortFingerprint(staticPublicKey: Uint8Array): string {
  const digest = hash(staticPublicKey);
  let out = '';
  for (let i = 0; i < 4; i++) out += digest[i]!.toString(16).padStart(2, '0');
  return out.toUpperCase();
}

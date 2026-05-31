/**
 * Crypto primitives for Noise_XX_25519_ChaChaPoly_SHA256, isolating the @noble
 * import surface so the rest of pairing depends on small, stable functions.
 *
 *   DH    : X25519           (@noble/curves)
 *   Cipher: ChaCha20-Poly1305 (@noble/ciphers) — AEAD with a 12-byte nonce,
 *           Noise uses a 64-bit counter in the low 8 bytes, big-endian-padded.
 *   Hash  : SHA-256          (@noble/hashes), HKDF for key derivation.
 */

import { chacha20poly1305 } from '@noble/ciphers/chacha';
import { x25519 } from '@noble/curves/ed25519';
import { hkdf } from '@noble/hashes/hkdf';
import { sha256 } from '@noble/hashes/sha2';

export const DH_LEN = 32;
export const HASH_LEN = 32;
export const TAG_LEN = 16;

export interface KeyPair {
  privateKey: Uint8Array;
  publicKey: Uint8Array;
}

export function generateKeyPair(): KeyPair {
  const privateKey = x25519.utils.randomPrivateKey();
  return { privateKey, publicKey: x25519.getPublicKey(privateKey) };
}

export function keyPairFromPrivate(privateKey: Uint8Array): KeyPair {
  return { privateKey, publicKey: x25519.getPublicKey(privateKey) };
}

export function dh(privateKey: Uint8Array, publicKey: Uint8Array): Uint8Array {
  return x25519.getSharedSecret(privateKey, publicKey);
}

export function hash(data: Uint8Array): Uint8Array {
  return sha256(data);
}

/**
 * Noise HKDF: returns `numOutputs` (2 or 3) 32-byte outputs from chaining key +
 * input keying material. Implemented via standard HKDF-Extract/Expand on SHA-256.
 */
export function hkdfNoise(
  chainingKey: Uint8Array,
  inputKeyMaterial: Uint8Array,
  numOutputs: 2 | 3,
): Uint8Array[] {
  // HKDF(salt=chainingKey, ikm). Expand with single-byte info 0x01,0x02,0x03.
  const okm = hkdf(sha256, inputKeyMaterial, chainingKey, undefined, HASH_LEN * numOutputs);
  const outputs: Uint8Array[] = [];
  for (let i = 0; i < numOutputs; i++) {
    outputs.push(okm.slice(i * HASH_LEN, (i + 1) * HASH_LEN));
  }
  return outputs;
}

function nonceToBytes(counter: bigint): Uint8Array {
  // Noise: 8-byte little-endian counter, zero-padded to the 12-byte AEAD nonce.
  // RFC 7539 / Noise spec: 4 zero bytes followed by the 64-bit little-endian n.
  const nonce = new Uint8Array(12);
  let n = counter;
  for (let i = 0; i < 8; i++) {
    nonce[4 + i] = Number(n & 0xffn);
    n >>= 8n;
  }
  return nonce;
}

export function aeadEncrypt(
  key: Uint8Array,
  counter: bigint,
  associatedData: Uint8Array,
  plaintext: Uint8Array,
): Uint8Array {
  const cipher = chacha20poly1305(key, nonceToBytes(counter), associatedData);
  return cipher.encrypt(plaintext);
}

export function aeadDecrypt(
  key: Uint8Array,
  counter: bigint,
  associatedData: Uint8Array,
  ciphertext: Uint8Array,
): Uint8Array {
  const cipher = chacha20poly1305(key, nonceToBytes(counter), associatedData);
  return cipher.decrypt(ciphertext);
}

export function concatBytes(...arrays: Uint8Array[]): Uint8Array {
  let total = 0;
  for (const a of arrays) total += a.length;
  const out = new Uint8Array(total);
  let offset = 0;
  for (const a of arrays) {
    out.set(a, offset);
    offset += a.length;
  }
  return out;
}

export function bytesEqual(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) return false;
  return true;
}

export function utf8Bytes(s: string): Uint8Array {
  // TextEncoder is available on Hermes (RN), modern browsers, and Node.
  return new TextEncoder().encode(s);
}

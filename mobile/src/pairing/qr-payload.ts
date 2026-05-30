/**
 * Parser for the desktop's pairing QR payload:
 *
 *   maverick://pair/v1?k=&e=&t=&r=&n=&f=
 *
 * Query parameters (all base64url unless noted):
 *   k  desktop static X25519 public key (32 bytes)            — required
 *   e  desktop ephemeral X25519 public key hint (32 bytes)    — optional
 *   t  one-time pairing token (opaque ASCII/base64url)        — required
 *   r  relay / rendezvous hint (URL string, percent-encoded)  — optional
 *   n  human-readable node name (UTF-8, percent-encoded)      — optional
 *   f  short fingerprint of `k` for out-of-band verification  — optional
 *
 * The parser is strict about scheme/host/version and the presence + length of
 * the required cryptographic fields, so a malformed or spoofed code is rejected
 * before any handshake begins.
 */

import { base64urlToBytes } from './base64url';

export interface PairingPayload {
  /** Desktop static public key (X25519, 32 bytes). */
  staticPublicKey: Uint8Array;
  /** Optional desktop ephemeral public key hint (32 bytes). */
  ephemeralPublicKey?: Uint8Array;
  /** One-time pairing token. */
  token: string;
  /** Optional relay / rendezvous hint. */
  relay?: string;
  /** Optional node name. */
  name?: string;
  /** Optional short fingerprint of the static key. */
  fingerprint?: string;
}

export class PairingParseError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'PairingParseError';
  }
}

const X25519_KEY_LEN = 32;

/**
 * Parse a `maverick://pair/v1?...` URI. Uses manual scheme/query parsing rather
 * than the WHATWG URL because RN/Hermes' URL support for custom schemes is
 * inconsistent across platforms.
 */
export function parsePairingPayload(uri: string): PairingPayload {
  const prefix = 'maverick://pair/v1';
  if (!uri.startsWith('maverick://')) {
    throw new PairingParseError('Not a maverick:// URI');
  }
  const qIndex = uri.indexOf('?');
  const base = qIndex >= 0 ? uri.slice(0, qIndex) : uri;
  if (base !== prefix) {
    throw new PairingParseError(`Unsupported pairing path/version: ${base}`);
  }
  const query = qIndex >= 0 ? uri.slice(qIndex + 1) : '';
  const params = parseQuery(query);

  const k = params.get('k');
  if (!k) throw new PairingParseError('Missing required param "k" (static key)');
  const staticPublicKey = decodeKey(k, 'k');

  const t = params.get('t');
  if (!t) throw new PairingParseError('Missing required param "t" (token)');

  const payload: PairingPayload = { staticPublicKey, token: t };

  const e = params.get('e');
  if (e !== undefined) payload.ephemeralPublicKey = decodeKey(e, 'e');

  const r = params.get('r');
  if (r !== undefined) payload.relay = r;

  const n = params.get('n');
  if (n !== undefined) payload.name = n;

  const f = params.get('f');
  if (f !== undefined) payload.fingerprint = f;

  return payload;
}

function parseQuery(query: string): Map<string, string> {
  const out = new Map<string, string>();
  if (query.length === 0) return out;
  for (const pair of query.split('&')) {
    if (pair.length === 0) continue;
    const eq = pair.indexOf('=');
    const rawKey = eq >= 0 ? pair.slice(0, eq) : pair;
    const rawVal = eq >= 0 ? pair.slice(eq + 1) : '';
    const key = safeDecodeURIComponent(rawKey);
    const val = safeDecodeURIComponent(rawVal);
    if (!out.has(key)) out.set(key, val);
  }
  return out;
}

function safeDecodeURIComponent(s: string): string {
  try {
    return decodeURIComponent(s);
  } catch {
    return s;
  }
}

function decodeKey(value: string, param: string): Uint8Array {
  let bytes: Uint8Array;
  try {
    bytes = base64urlToBytes(value);
  } catch (e) {
    throw new PairingParseError(`Param "${param}" is not valid base64url`);
  }
  if (bytes.length !== X25519_KEY_LEN) {
    throw new PairingParseError(
      `Param "${param}" must be ${X25519_KEY_LEN} bytes, got ${bytes.length}`,
    );
  }
  return bytes;
}

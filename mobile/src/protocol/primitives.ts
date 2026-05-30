/**
 * Wire-format primitives shared by every codec.
 *
 * The desktop encodes with Swift's `JSONEncoder` configured with
 * `.dateEncodingStrategy = .iso8601` and the *default* (camelCase) key
 * strategy. UUIDs use `UUID.uuidString` (UPPERCASE, hyphenated), and `Data`
 * uses standard base64 (`base64EncodedString()`).
 *
 * These helpers reproduce that contract and are environment-independent: they
 * do NOT rely on Node's Buffer or browser atob/btoa, so they behave
 * identically on iOS/Android (Hermes) and web.
 */

// ---------------------------------------------------------------------------
// ISO8601 dates (Swift .iso8601 strategy → second precision, trailing "Z").
// ---------------------------------------------------------------------------

export class DecodeError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'DecodeError';
  }
}

/** Encode a Date as ISO8601 with second precision and a trailing `Z`. */
export function encodeISO8601(date: Date): string {
  if (Number.isNaN(date.getTime())) {
    throw new DecodeError('Cannot encode an invalid Date');
  }
  // Swift's .iso8601 drops sub-second precision: 2026-05-31T12:34:56Z
  return date.toISOString().replace(/\.\d{3}Z$/, 'Z');
}

/** Decode an ISO8601 string into a Date, throwing on malformed input. */
export function decodeISO8601(raw: unknown): Date {
  if (typeof raw !== 'string') {
    throw new DecodeError(`Expected ISO8601 string, got ${typeof raw}`);
  }
  const ms = Date.parse(raw);
  if (Number.isNaN(ms)) {
    throw new DecodeError(`Malformed ISO8601 date: ${raw}`);
  }
  return new Date(ms);
}

// ---------------------------------------------------------------------------
// UUID — Swift uses UPPERCASE uuidString on encode; decode is case-insensitive.
// ---------------------------------------------------------------------------

const UUID_RE =
  /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;

/** Validate + normalise a UUID string to Swift's UPPERCASE canonical form. */
export function decodeUUID(raw: unknown): string {
  if (typeof raw !== 'string' || !UUID_RE.test(raw)) {
    throw new DecodeError(`Malformed UUID: ${String(raw)}`);
  }
  return raw.toUpperCase();
}

/** Encode a UUID string in Swift's UPPERCASE canonical form. */
export function encodeUUID(value: string): string {
  return decodeUUID(value);
}

/**
 * RFC-4122 v4 UUID generator (UPPERCASE, matching Swift's uuidString).
 *
 * Randomness comes from the platform CSPRNG via `crypto.getRandomValues`
 * (Hermes 0.71+, web, and Node 19+ all expose `globalThis.crypto`). We never
 * use `Math.random()`, which is not cryptographically secure.
 */
export function randomUUID(): string {
  const bytes = new Uint8Array(16);
  const webcrypto = (globalThis as { crypto?: Crypto }).crypto;
  if (!webcrypto || typeof webcrypto.getRandomValues !== 'function') {
    throw new DecodeError('No CSPRNG (crypto.getRandomValues) available');
  }
  webcrypto.getRandomValues(bytes);
  // Set version (4) and variant (10xx) bits per RFC-4122 §4.4.
  bytes[6] = (bytes[6]! & 0x0f) | 0x40;
  bytes[8] = (bytes[8]! & 0x3f) | 0x80;
  const hex: string[] = [];
  for (let i = 0; i < 16; i++) {
    hex.push(bytes[i]!.toString(16).padStart(2, '0'));
  }
  const s = hex.join('');
  return (
    s.slice(0, 8) +
    '-' +
    s.slice(8, 12) +
    '-' +
    s.slice(12, 16) +
    '-' +
    s.slice(16, 20) +
    '-' +
    s.slice(20)
  ).toUpperCase();
}

// ---------------------------------------------------------------------------
// Base64 — standard alphabet, matching Swift's Data(base64Encoded:) round-trip.
// ---------------------------------------------------------------------------

const B64_ALPHABET =
  'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
const B64_LOOKUP: Record<string, number> = (() => {
  const map: Record<string, number> = {};
  for (let i = 0; i < B64_ALPHABET.length; i++) {
    map[B64_ALPHABET[i]!] = i;
  }
  return map;
})();

/** Encode raw bytes to a standard base64 string. */
export function encodeBase64(bytes: Uint8Array): string {
  let out = '';
  for (let i = 0; i < bytes.length; i += 3) {
    const b0 = bytes[i]!;
    const b1 = i + 1 < bytes.length ? bytes[i + 1]! : 0;
    const b2 = i + 2 < bytes.length ? bytes[i + 2]! : 0;
    out += B64_ALPHABET[b0 >> 2];
    out += B64_ALPHABET[((b0 & 0x03) << 4) | (b1 >> 4)];
    out += i + 1 < bytes.length ? B64_ALPHABET[((b1 & 0x0f) << 2) | (b2 >> 6)] : '=';
    out += i + 2 < bytes.length ? B64_ALPHABET[b2 & 0x3f] : '=';
  }
  return out;
}

/** Decode a standard base64 string to raw bytes, throwing on bad input. */
export function decodeBase64(raw: unknown): Uint8Array {
  if (typeof raw !== 'string') {
    throw new DecodeError(`Expected base64 string, got ${typeof raw}`);
  }
  const clean = raw.replace(/[\r\n]/g, '');
  if (clean.length % 4 !== 0) {
    throw new DecodeError('Invalid base64 length');
  }
  const padLen = clean.endsWith('==') ? 2 : clean.endsWith('=') ? 1 : 0;
  const byteLen = (clean.length / 4) * 3 - padLen;
  const out = new Uint8Array(byteLen);
  let o = 0;
  for (let i = 0; i < clean.length; i += 4) {
    const c0 = clean[i]!;
    const c1 = clean[i + 1]!;
    const c2 = clean[i + 2]!;
    const c3 = clean[i + 3]!;
    const e0 = B64_LOOKUP[c0];
    const e1 = B64_LOOKUP[c1];
    if (e0 === undefined || e1 === undefined) {
      throw new DecodeError('Invalid base64 character');
    }
    const e2 = c2 === '=' ? 0 : B64_LOOKUP[c2];
    const e3 = c3 === '=' ? 0 : B64_LOOKUP[c3];
    if ((c2 !== '=' && e2 === undefined) || (c3 !== '=' && e3 === undefined)) {
      throw new DecodeError('Invalid base64 character');
    }
    const triple = (e0 << 18) | (e1 << 12) | ((e2 ?? 0) << 6) | (e3 ?? 0);
    if (o < byteLen) out[o++] = (triple >> 16) & 0xff;
    if (o < byteLen) out[o++] = (triple >> 8) & 0xff;
    if (o < byteLen) out[o++] = triple & 0xff;
  }
  return out;
}

// ---------------------------------------------------------------------------
// Field readers — strict accessors over a decoded JSON object.
// ---------------------------------------------------------------------------

export type JSONObject = Record<string, unknown>;

export function asObject(value: unknown): JSONObject {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) {
    throw new DecodeError('Expected a JSON object');
  }
  return value as JSONObject;
}

export function reqString(obj: JSONObject, key: string): string {
  const v = obj[key];
  if (typeof v !== 'string') {
    throw new DecodeError(`Missing/invalid string field "${key}"`);
  }
  return v;
}

export function optString(obj: JSONObject, key: string): string | undefined {
  const v = obj[key];
  if (v === undefined || v === null) return undefined;
  if (typeof v !== 'string') {
    throw new DecodeError(`Invalid optional string field "${key}"`);
  }
  return v;
}

export function reqInt(obj: JSONObject, key: string): number {
  const v = obj[key];
  if (typeof v !== 'number' || !Number.isFinite(v)) {
    throw new DecodeError(`Missing/invalid number field "${key}"`);
  }
  return v;
}

export function optInt(obj: JSONObject, key: string): number | undefined {
  const v = obj[key];
  if (v === undefined || v === null) return undefined;
  if (typeof v !== 'number' || !Number.isFinite(v)) {
    throw new DecodeError(`Invalid optional number field "${key}"`);
  }
  return v;
}

export function reqNumber(obj: JSONObject, key: string): number {
  return reqInt(obj, key);
}

export function optNumber(obj: JSONObject, key: string): number | undefined {
  return optInt(obj, key);
}

export function reqBool(obj: JSONObject, key: string): boolean {
  const v = obj[key];
  if (typeof v !== 'boolean') {
    throw new DecodeError(`Missing/invalid boolean field "${key}"`);
  }
  return v;
}

/** Swift uses `decodeIfPresent(...) ?? false` for several booleans. */
export function optBool(obj: JSONObject, key: string, fallback = false): boolean {
  const v = obj[key];
  if (v === undefined || v === null) return fallback;
  if (typeof v !== 'boolean') {
    throw new DecodeError(`Invalid optional boolean field "${key}"`);
  }
  return v;
}

export function reqArray(obj: JSONObject, key: string): unknown[] {
  const v = obj[key];
  if (!Array.isArray(v)) {
    throw new DecodeError(`Missing/invalid array field "${key}"`);
  }
  return v;
}

/**
 * base64url <-> bytes, padding-optional, no external deps. The QR payload uses
 * URL-safe base64 (`-`/`_`, padding stripped) so it survives QR + URI encoding.
 */

import { decodeBase64, encodeBase64 } from '@/protocol';

export function base64urlToBytes(value: string): Uint8Array {
  let std = value.replace(/-/g, '+').replace(/_/g, '/');
  const pad = std.length % 4;
  if (pad === 2) std += '==';
  else if (pad === 3) std += '=';
  else if (pad === 1) throw new Error('Invalid base64url length');
  return decodeBase64(std);
}

export function bytesToBase64url(bytes: Uint8Array): string {
  return encodeBase64(bytes).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

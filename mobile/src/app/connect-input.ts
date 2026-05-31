/**
 * Parsing/validation helpers for the manual host:port entry fallback on the
 * Connect screen. Accepts a bare host, `host:port`, or an explicit port field,
 * and validates the resulting target before the client dials it.
 */

import { ConnectTarget } from './maverick-client';

export const DEFAULT_PORT = 8765;

export interface ParseResult {
  ok: boolean;
  target?: ConnectTarget;
  error?: string;
}

/**
 * Build a ConnectTarget from the manual fields. `port` may be empty (defaults
 * to 8765) or embedded in `host` as `host:port` (the port field wins if both
 * are present and non-empty).
 */
export function parseManualTarget(
  host: string,
  port: string,
  token: string,
): ParseResult {
  let h = host.trim();
  if (h.length === 0) return { ok: false, error: 'Enter your Mac’s address.' };

  const portField = port.trim();
  // Allow host:port in the host field; the explicit port field wins when set.
  // The `]` guard skips the colons inside a bracketed IPv6 literal.
  const colon = h.lastIndexOf(':');
  let embeddedPort = '';
  if (colon > 0 && h.indexOf(']') < colon) {
    embeddedPort = h.slice(colon + 1);
    h = h.slice(0, colon);
  }
  const portStr = portField.length > 0 ? portField : embeddedPort;

  const p = portStr.length === 0 ? DEFAULT_PORT : Number(portStr);
  if (!Number.isInteger(p) || p < 1 || p > 65535) {
    return { ok: false, error: 'Port must be between 1 and 65535.' };
  }

  const target: ConnectTarget = { host: h, port: p };
  const t = token.trim();
  if (t.length > 0) target.token = t;
  return { ok: true, target };
}

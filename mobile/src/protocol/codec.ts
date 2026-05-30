/**
 * `MaverickJSON` equivalent — string<->message helpers that go through
 * `JSON.stringify`/`JSON.parse` and the per-type codecs. The per-type encoders
 * already produce ISO8601 dates / base64 / UPPERCASE UUIDs, so the only job
 * here is the JSON string boundary the WebSocket transport speaks.
 */

import {
  ClientMessage,
  decodeClientMessage,
  encodeClientMessage,
} from './client-message';
import { DecodeError } from './primitives';
import {
  decodeServerMessage,
  encodeServerMessage,
  ServerMessage,
} from './server-message';

export function encodeClientMessageToString(msg: ClientMessage): string {
  return JSON.stringify(encodeClientMessage(msg));
}

export function decodeClientMessageFromString(text: string): ClientMessage {
  let parsed: unknown;
  try {
    parsed = JSON.parse(text);
  } catch (e) {
    throw new DecodeError(`Malformed JSON: ${(e as Error).message}`);
  }
  return decodeClientMessage(parsed);
}

export function encodeServerMessageToString(msg: ServerMessage): string {
  return JSON.stringify(encodeServerMessage(msg));
}

export function decodeServerMessageFromString(text: string): ServerMessage {
  let parsed: unknown;
  try {
    parsed = JSON.parse(text);
  } catch (e) {
    throw new DecodeError(`Malformed JSON: ${(e as Error).message}`);
  }
  return decodeServerMessage(parsed);
}

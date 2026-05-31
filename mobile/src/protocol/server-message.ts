/**
 * Port of `ServerMessage` from Messages.swift.
 *
 * snake_case `type` discriminator, flat camelCase sibling keys. `complete` and
 * `truncated` default to false when absent (Swift `decodeIfPresent ?? false`).
 */

import { AgentEvent, decodeAgentEvent, encodeAgentEvent } from './agent-event';
import {
  asObject,
  decodeUUID,
  DecodeError,
  encodeUUID,
  JSONObject,
  optBool,
  reqArray,
  reqString,
} from './primitives';
import {
  decodeDirectoryEntry,
  decodeGitStatus,
  decodeIndexEntry,
  decodeSessionInfo,
  DirectoryEntry,
  encodeDirectoryEntry,
  encodeGitStatus,
  encodeIndexEntry,
  encodeSessionInfo,
  GitStatus,
  IndexEntry,
  SessionInfo,
} from './structs';

export type ServerMessage =
  | { type: 'session_list'; sessions: SessionInfo[] }
  | { type: 'session_created'; session: SessionInfo }
  | { type: 'output'; sessionId: string; data: string }
  | { type: 'scrollback'; sessionId: string; data: string }
  | { type: 'session_closed'; sessionId: string }
  | { type: 'error'; message: string }
  | { type: 'file_uploaded'; uploadId: string; path: string }
  | { type: 'file_upload_failed'; uploadId: string; message: string }
  | {
      type: 'directory_listing';
      requestId: string;
      path: string;
      entries: DirectoryEntry[];
    }
  | { type: 'directory_listing_failed'; requestId: string; message: string }
  | {
      type: 'index_chunk';
      requestId: string;
      root: string;
      entries: IndexEntry[];
      complete: boolean;
    }
  | { type: 'index_failed'; requestId: string; message: string }
  | { type: 'git_status_result'; requestId: string; status: GitStatus }
  | { type: 'git_status_failed'; requestId: string; message: string }
  | {
      type: 'git_diff_result';
      requestId: string;
      file: string;
      diff: string;
      truncated: boolean;
    }
  | { type: 'git_diff_failed'; requestId: string; message: string }
  | { type: 'agent_event'; sessionId: string; event: AgentEvent }
  | { type: 'agent_session_created'; session: SessionInfo };

export function decodeServerMessage(value: unknown): ServerMessage {
  const o = asObject(value);
  const type = o.type;
  if (typeof type !== 'string') {
    throw new DecodeError('ServerMessage is missing string "type"');
  }
  switch (type) {
    case 'session_list':
      return { type, sessions: reqArray(o, 'sessions').map(decodeSessionInfo) };
    case 'session_created':
      return { type, session: decodeSessionInfo(o.session) };
    case 'output':
      return { type, sessionId: decodeUUID(o.sessionId), data: reqString(o, 'data') };
    case 'scrollback':
      return { type, sessionId: decodeUUID(o.sessionId), data: reqString(o, 'data') };
    case 'session_closed':
      return { type, sessionId: decodeUUID(o.sessionId) };
    case 'error':
      return { type, message: reqString(o, 'message') };
    case 'file_uploaded':
      return { type, uploadId: decodeUUID(o.uploadId), path: reqString(o, 'path') };
    case 'file_upload_failed':
      return {
        type,
        uploadId: decodeUUID(o.uploadId),
        message: reqString(o, 'message'),
      };
    case 'directory_listing':
      return {
        type,
        requestId: decodeUUID(o.requestId),
        path: reqString(o, 'path'),
        entries: reqArray(o, 'entries').map(decodeDirectoryEntry),
      };
    case 'directory_listing_failed':
      return {
        type,
        requestId: decodeUUID(o.requestId),
        message: reqString(o, 'message'),
      };
    case 'index_chunk':
      return {
        type,
        requestId: decodeUUID(o.requestId),
        root: reqString(o, 'root'),
        entries: reqArray(o, 'entries').map(decodeIndexEntry),
        complete: optBool(o, 'complete'),
      };
    case 'index_failed':
      return {
        type,
        requestId: decodeUUID(o.requestId),
        message: reqString(o, 'message'),
      };
    case 'git_status_result':
      return {
        type,
        requestId: decodeUUID(o.requestId),
        status: decodeGitStatus(o.status),
      };
    case 'git_status_failed':
      return {
        type,
        requestId: decodeUUID(o.requestId),
        message: reqString(o, 'message'),
      };
    case 'git_diff_result':
      return {
        type,
        requestId: decodeUUID(o.requestId),
        file: reqString(o, 'file'),
        diff: reqString(o, 'diff'),
        truncated: optBool(o, 'truncated'),
      };
    case 'git_diff_failed':
      return {
        type,
        requestId: decodeUUID(o.requestId),
        message: reqString(o, 'message'),
      };
    case 'agent_event':
      return {
        type,
        sessionId: decodeUUID(o.sessionId),
        event: decodeAgentEvent(o.event),
      };
    case 'agent_session_created':
      return { type, session: decodeSessionInfo(o.session) };
    default:
      throw new DecodeError(`Unknown ServerMessage type: ${type}`);
  }
}

export function encodeServerMessage(msg: ServerMessage): JSONObject {
  switch (msg.type) {
    case 'session_list':
      return { type: msg.type, sessions: msg.sessions.map(encodeSessionInfo) };
    case 'session_created':
      return { type: msg.type, session: encodeSessionInfo(msg.session) };
    case 'output':
      return { type: msg.type, sessionId: encodeUUID(msg.sessionId), data: msg.data };
    case 'scrollback':
      return { type: msg.type, sessionId: encodeUUID(msg.sessionId), data: msg.data };
    case 'session_closed':
      return { type: msg.type, sessionId: encodeUUID(msg.sessionId) };
    case 'error':
      return { type: msg.type, message: msg.message };
    case 'file_uploaded':
      return { type: msg.type, uploadId: encodeUUID(msg.uploadId), path: msg.path };
    case 'file_upload_failed':
      return {
        type: msg.type,
        uploadId: encodeUUID(msg.uploadId),
        message: msg.message,
      };
    case 'directory_listing':
      return {
        type: msg.type,
        requestId: encodeUUID(msg.requestId),
        path: msg.path,
        entries: msg.entries.map(encodeDirectoryEntry),
      };
    case 'directory_listing_failed':
      return {
        type: msg.type,
        requestId: encodeUUID(msg.requestId),
        message: msg.message,
      };
    case 'index_chunk':
      return {
        type: msg.type,
        requestId: encodeUUID(msg.requestId),
        root: msg.root,
        entries: msg.entries.map(encodeIndexEntry),
        complete: msg.complete,
      };
    case 'index_failed':
      return {
        type: msg.type,
        requestId: encodeUUID(msg.requestId),
        message: msg.message,
      };
    case 'git_status_result':
      return {
        type: msg.type,
        requestId: encodeUUID(msg.requestId),
        status: encodeGitStatus(msg.status),
      };
    case 'git_status_failed':
      return {
        type: msg.type,
        requestId: encodeUUID(msg.requestId),
        message: msg.message,
      };
    case 'git_diff_result':
      return {
        type: msg.type,
        requestId: encodeUUID(msg.requestId),
        file: msg.file,
        diff: msg.diff,
        truncated: msg.truncated,
      };
    case 'git_diff_failed':
      return {
        type: msg.type,
        requestId: encodeUUID(msg.requestId),
        message: msg.message,
      };
    case 'agent_event':
      return {
        type: msg.type,
        sessionId: encodeUUID(msg.sessionId),
        event: encodeAgentEvent(msg.event),
      };
    case 'agent_session_created':
      return { type: msg.type, session: encodeSessionInfo(msg.session) };
  }
}

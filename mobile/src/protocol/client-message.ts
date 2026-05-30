/**
 * Port of `ClientMessage` from Messages.swift.
 *
 * snake_case `type` discriminator, flat camelCase sibling keys. Optional cwd /
 * path use encodeIfPresent (omitted when undefined). `refresh` and `staged`
 * default to false when absent on decode (Swift `decodeIfPresent ?? false`).
 */

import {
  AgentProvider,
  AGENT_PROVIDERS,
  isMember,
  SessionMode,
  SESSION_MODES,
} from './enums';
import {
  asObject,
  decodeUUID,
  DecodeError,
  encodeUUID,
  JSONObject,
  optBool,
  optString,
  reqBool,
  reqInt,
  reqString,
} from './primitives';

export type ClientMessage =
  | { type: 'list_sessions' }
  | { type: 'create_session'; name: string; shell: string; cwd?: string }
  | { type: 'attach_session'; sessionId: string }
  | { type: 'input'; sessionId: string; data: string }
  | { type: 'resize'; sessionId: string; cols: number; rows: number }
  | { type: 'close_session'; sessionId: string }
  | { type: 'upload_file'; uploadId: string; filename: string; data: string }
  | { type: 'list_directory'; requestId: string; path?: string }
  | { type: 'index_project'; requestId: string; path: string; refresh: boolean }
  | { type: 'git_status'; requestId: string; path: string }
  | {
      type: 'git_diff';
      requestId: string;
      path: string;
      file: string;
      staged: boolean;
    }
  | {
      type: 'create_agent_session';
      name: string;
      provider: AgentProvider;
      cwd?: string;
    }
  | { type: 'switch_session_mode'; sessionId: string; mode: SessionMode }
  | { type: 'agent_input'; sessionId: string; text: string }
  | {
      type: 'permission_response';
      sessionId: string;
      requestId: string;
      allowed: boolean;
    };

export function decodeClientMessage(value: unknown): ClientMessage {
  const o = asObject(value);
  const type = o.type;
  if (typeof type !== 'string') {
    throw new DecodeError('ClientMessage is missing string "type"');
  }
  switch (type) {
    case 'list_sessions':
      return { type };
    case 'create_session': {
      const msg: ClientMessage = {
        type,
        name: reqString(o, 'name'),
        shell: reqString(o, 'shell'),
      };
      const cwd = optString(o, 'cwd');
      if (cwd !== undefined) msg.cwd = cwd;
      return msg;
    }
    case 'attach_session':
      return { type, sessionId: decodeUUID(o.sessionId) };
    case 'input':
      return { type, sessionId: decodeUUID(o.sessionId), data: reqString(o, 'data') };
    case 'resize':
      return {
        type,
        sessionId: decodeUUID(o.sessionId),
        cols: reqInt(o, 'cols'),
        rows: reqInt(o, 'rows'),
      };
    case 'close_session':
      return { type, sessionId: decodeUUID(o.sessionId) };
    case 'upload_file':
      return {
        type,
        uploadId: decodeUUID(o.uploadId),
        filename: reqString(o, 'filename'),
        data: reqString(o, 'data'),
      };
    case 'list_directory': {
      const msg: ClientMessage = { type, requestId: decodeUUID(o.requestId) };
      const path = optString(o, 'path');
      if (path !== undefined) msg.path = path;
      return msg;
    }
    case 'index_project':
      return {
        type,
        requestId: decodeUUID(o.requestId),
        path: reqString(o, 'path'),
        refresh: optBool(o, 'refresh'),
      };
    case 'git_status':
      return { type, requestId: decodeUUID(o.requestId), path: reqString(o, 'path') };
    case 'git_diff':
      return {
        type,
        requestId: decodeUUID(o.requestId),
        path: reqString(o, 'path'),
        file: reqString(o, 'file'),
        staged: optBool(o, 'staged'),
      };
    case 'create_agent_session': {
      const provider = o.provider;
      if (!isMember(AGENT_PROVIDERS, provider)) {
        throw new DecodeError(`Unknown provider: ${String(provider)}`);
      }
      const msg: ClientMessage = { type, name: reqString(o, 'name'), provider };
      const cwd = optString(o, 'cwd');
      if (cwd !== undefined) msg.cwd = cwd;
      return msg;
    }
    case 'switch_session_mode': {
      const mode = o.mode;
      if (!isMember(SESSION_MODES, mode)) {
        throw new DecodeError(`Unknown mode: ${String(mode)}`);
      }
      return { type, sessionId: decodeUUID(o.sessionId), mode };
    }
    case 'agent_input':
      return { type, sessionId: decodeUUID(o.sessionId), text: reqString(o, 'text') };
    case 'permission_response':
      return {
        type,
        sessionId: decodeUUID(o.sessionId),
        requestId: decodeUUID(o.requestId),
        allowed: reqBool(o, 'allowed'),
      };
    default:
      throw new DecodeError(`Unknown ClientMessage type: ${type}`);
  }
}

export function encodeClientMessage(msg: ClientMessage): JSONObject {
  switch (msg.type) {
    case 'list_sessions':
      return { type: msg.type };
    case 'create_session': {
      const out: JSONObject = { type: msg.type, name: msg.name, shell: msg.shell };
      if (msg.cwd !== undefined) out.cwd = msg.cwd;
      return out;
    }
    case 'attach_session':
      return { type: msg.type, sessionId: encodeUUID(msg.sessionId) };
    case 'input':
      return { type: msg.type, sessionId: encodeUUID(msg.sessionId), data: msg.data };
    case 'resize':
      return {
        type: msg.type,
        sessionId: encodeUUID(msg.sessionId),
        cols: msg.cols,
        rows: msg.rows,
      };
    case 'close_session':
      return { type: msg.type, sessionId: encodeUUID(msg.sessionId) };
    case 'upload_file':
      return {
        type: msg.type,
        uploadId: encodeUUID(msg.uploadId),
        filename: msg.filename,
        data: msg.data,
      };
    case 'list_directory': {
      const out: JSONObject = { type: msg.type, requestId: encodeUUID(msg.requestId) };
      if (msg.path !== undefined) out.path = msg.path;
      return out;
    }
    case 'index_project':
      return {
        type: msg.type,
        requestId: encodeUUID(msg.requestId),
        path: msg.path,
        refresh: msg.refresh,
      };
    case 'git_status':
      return { type: msg.type, requestId: encodeUUID(msg.requestId), path: msg.path };
    case 'git_diff':
      return {
        type: msg.type,
        requestId: encodeUUID(msg.requestId),
        path: msg.path,
        file: msg.file,
        staged: msg.staged,
      };
    case 'create_agent_session': {
      const out: JSONObject = {
        type: msg.type,
        name: msg.name,
        provider: msg.provider,
      };
      if (msg.cwd !== undefined) out.cwd = msg.cwd;
      return out;
    }
    case 'switch_session_mode':
      return { type: msg.type, sessionId: encodeUUID(msg.sessionId), mode: msg.mode };
    case 'agent_input':
      return { type: msg.type, sessionId: encodeUUID(msg.sessionId), text: msg.text };
    case 'permission_response':
      return {
        type: msg.type,
        sessionId: encodeUUID(msg.sessionId),
        requestId: encodeUUID(msg.requestId),
        allowed: msg.allowed,
      };
  }
}

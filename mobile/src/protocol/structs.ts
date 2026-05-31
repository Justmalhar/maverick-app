/**
 * Port of the supporting `struct` value types from MaverickProtocol:
 * SessionInfo, DirectoryEntry, IndexEntry, GitFileStatus, GitStatus,
 * ToolCallEvent, FileDiff, PermissionEvent, ElicitationField.
 *
 * All keys are camelCase because the desktop's JSONEncoder uses the default key
 * strategy. `Optional` Swift fields are encoded only when present
 * (`encodeIfPresent`), so we omit `undefined` keys to keep the wire byte-exact.
 */

import {
  AgentProvider,
  AGENT_PROVIDERS,
  EffortLevel,
  EFFORT_LEVELS,
  isMember,
  SessionMode,
  SESSION_MODES,
} from './enums';
import {
  asObject,
  decodeISO8601,
  decodeUUID,
  DecodeError,
  encodeISO8601,
  encodeUUID,
  JSONObject,
  optInt,
  optNumber,
  optString,
  reqArray,
  reqBool,
  reqInt,
  reqString,
} from './primitives';
import {
  decodeToolKind,
  encodeToolKind,
  ToolKind,
} from './tool-kind';

// --- SessionInfo ----------------------------------------------------------

export interface SessionInfo {
  id: string;
  name: string;
  shell: string;
  createdAt: Date;
  agentProvider?: AgentProvider;
  sessionMode?: SessionMode;
}

export function decodeSessionInfo(value: unknown): SessionInfo {
  const o = asObject(value);
  const provider = optString(o, 'agentProvider');
  const mode = optString(o, 'sessionMode');
  if (provider !== undefined && !isMember(AGENT_PROVIDERS, provider)) {
    throw new DecodeError(`Unknown agentProvider: ${provider}`);
  }
  if (mode !== undefined && !isMember(SESSION_MODES, mode)) {
    throw new DecodeError(`Unknown sessionMode: ${mode}`);
  }
  const info: SessionInfo = {
    id: decodeUUID(o.id),
    name: reqString(o, 'name'),
    shell: reqString(o, 'shell'),
    createdAt: decodeISO8601(o.createdAt),
  };
  if (provider !== undefined) info.agentProvider = provider;
  if (mode !== undefined) info.sessionMode = mode;
  return info;
}

export function encodeSessionInfo(info: SessionInfo): JSONObject {
  const out: JSONObject = {
    id: encodeUUID(info.id),
    name: info.name,
    shell: info.shell,
    createdAt: encodeISO8601(info.createdAt),
  };
  if (info.agentProvider !== undefined) out.agentProvider = info.agentProvider;
  if (info.sessionMode !== undefined) out.sessionMode = info.sessionMode;
  return out;
}

// --- DirectoryEntry --------------------------------------------------------

export interface DirectoryEntry {
  name: string;
  isDirectory: boolean;
  isHidden: boolean;
}

export function decodeDirectoryEntry(value: unknown): DirectoryEntry {
  const o = asObject(value);
  return {
    name: reqString(o, 'name'),
    isDirectory: reqBool(o, 'isDirectory'),
    isHidden: reqBool(o, 'isHidden'),
  };
}

export function encodeDirectoryEntry(e: DirectoryEntry): JSONObject {
  return { name: e.name, isDirectory: e.isDirectory, isHidden: e.isHidden };
}

// --- IndexEntry ------------------------------------------------------------

export interface IndexEntry {
  path: string;
  isDirectory: boolean;
  size?: number;
}

export function decodeIndexEntry(value: unknown): IndexEntry {
  const o = asObject(value);
  const entry: IndexEntry = {
    path: reqString(o, 'path'),
    isDirectory: reqBool(o, 'isDirectory'),
  };
  const size = optInt(o, 'size');
  if (size !== undefined) entry.size = size;
  return entry;
}

export function encodeIndexEntry(e: IndexEntry): JSONObject {
  const out: JSONObject = { path: e.path, isDirectory: e.isDirectory };
  if (e.size !== undefined) out.size = e.size;
  return out;
}

// --- GitFileStatus / GitStatus --------------------------------------------

export interface GitFileStatus {
  path: string;
  status: string;
  staged: boolean;
}

export function decodeGitFileStatus(value: unknown): GitFileStatus {
  const o = asObject(value);
  return {
    path: reqString(o, 'path'),
    status: reqString(o, 'status'),
    staged: reqBool(o, 'staged'),
  };
}

export function encodeGitFileStatus(s: GitFileStatus): JSONObject {
  return { path: s.path, status: s.status, staged: s.staged };
}

export interface GitStatus {
  isRepo: boolean;
  branch?: string;
  ahead: number;
  behind: number;
  files: GitFileStatus[];
}

export function decodeGitStatus(value: unknown): GitStatus {
  const o = asObject(value);
  const status: GitStatus = {
    isRepo: reqBool(o, 'isRepo'),
    ahead: reqInt(o, 'ahead'),
    behind: reqInt(o, 'behind'),
    files: reqArray(o, 'files').map(decodeGitFileStatus),
  };
  const branch = optString(o, 'branch');
  if (branch !== undefined) status.branch = branch;
  return status;
}

export function encodeGitStatus(s: GitStatus): JSONObject {
  const out: JSONObject = {
    isRepo: s.isRepo,
    ahead: s.ahead,
    behind: s.behind,
    files: s.files.map(encodeGitFileStatus),
  };
  if (s.branch !== undefined) out.branch = s.branch;
  return out;
}

// --- FileDiff --------------------------------------------------------------

export interface FileDiff {
  path: string;
  added: number;
  removed: number;
}

export function decodeFileDiff(value: unknown): FileDiff {
  const o = asObject(value);
  return {
    path: reqString(o, 'path'),
    added: reqInt(o, 'added'),
    removed: reqInt(o, 'removed'),
  };
}

export function encodeFileDiff(d: FileDiff): JSONObject {
  return { path: d.path, added: d.added, removed: d.removed };
}

// --- ToolCallEvent ---------------------------------------------------------

export interface ToolCallEvent {
  id: string;
  tool: ToolKind;
  inputSummary: string;
  result?: string;
  error?: string;
  durationMs?: number;
  fileDiffs?: FileDiff[];
  effort?: EffortLevel;
}

export function decodeToolCallEvent(value: unknown): ToolCallEvent {
  const o = asObject(value);
  const event: ToolCallEvent = {
    id: reqString(o, 'id'),
    tool: decodeToolKind(o.tool),
    inputSummary: reqString(o, 'inputSummary'),
  };
  const result = optString(o, 'result');
  if (result !== undefined) event.result = result;
  const error = optString(o, 'error');
  if (error !== undefined) event.error = error;
  const durationMs = optInt(o, 'durationMs');
  if (durationMs !== undefined) event.durationMs = durationMs;
  if (o.fileDiffs !== undefined && o.fileDiffs !== null) {
    event.fileDiffs = reqArray(o, 'fileDiffs').map(decodeFileDiff);
  }
  const effort = optString(o, 'effort');
  if (effort !== undefined) {
    if (!isMember(EFFORT_LEVELS, effort)) {
      throw new DecodeError(`Unknown effort: ${effort}`);
    }
    event.effort = effort;
  }
  return event;
}

export function encodeToolCallEvent(e: ToolCallEvent): JSONObject {
  const out: JSONObject = {
    id: e.id,
    tool: encodeToolKind(e.tool),
    inputSummary: e.inputSummary,
  };
  if (e.result !== undefined) out.result = e.result;
  if (e.error !== undefined) out.error = e.error;
  if (e.durationMs !== undefined) out.durationMs = e.durationMs;
  if (e.fileDiffs !== undefined) out.fileDiffs = e.fileDiffs.map(encodeFileDiff);
  if (e.effort !== undefined) out.effort = e.effort;
  return out;
}

// --- PermissionEvent -------------------------------------------------------

export interface PermissionEvent {
  requestId: string;
  tool: string;
  inputSummary: string;
  ruleMatched?: string;
}

export function decodePermissionEvent(value: unknown): PermissionEvent {
  const o = asObject(value);
  const event: PermissionEvent = {
    requestId: reqString(o, 'requestId'),
    tool: reqString(o, 'tool'),
    inputSummary: reqString(o, 'inputSummary'),
  };
  const ruleMatched = optString(o, 'ruleMatched');
  if (ruleMatched !== undefined) event.ruleMatched = ruleMatched;
  return event;
}

export function encodePermissionEvent(e: PermissionEvent): JSONObject {
  const out: JSONObject = {
    requestId: e.requestId,
    tool: e.tool,
    inputSummary: e.inputSummary,
  };
  if (e.ruleMatched !== undefined) out.ruleMatched = e.ruleMatched;
  return out;
}

// --- ElicitationField ------------------------------------------------------

export interface ElicitationField {
  name: string;
  type: string;
  description: string;
  required: boolean;
}

export function decodeElicitationField(value: unknown): ElicitationField {
  const o = asObject(value);
  return {
    name: reqString(o, 'name'),
    type: reqString(o, 'type'),
    description: reqString(o, 'description'),
    required: reqBool(o, 'required'),
  };
}

export function encodeElicitationField(f: ElicitationField): JSONObject {
  return {
    name: f.name,
    type: f.type,
    description: f.description,
    required: f.required,
  };
}

// Re-export numeric helper used by ServerMessage cost (Double) decoding.
export { optNumber };

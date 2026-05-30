import {
  AgentEvent,
  asObject,
  ClientMessage,
  customTool,
  decodeAgentEvent,
  decodeBase64,
  decodeClientMessage,
  decodeClientMessageFromString,
  decodeISO8601,
  decodeServerMessage,
  decodeServerMessageFromString,
  decodeToolKind,
  decodeUUID,
  encodeAgentEvent,
  encodeBase64,
  encodeClientMessage,
  encodeClientMessageToString,
  encodeISO8601,
  encodeServerMessage,
  encodeServerMessageToString,
  encodeToolKind,
  optBool,
  optInt,
  optString,
  randomUUID,
  reqArray,
  reqBool,
  reqInt,
  reqNumber,
  reqString,
  ServerMessage,
  tool,
} from './index';

// A canonical UUID string in Swift's UPPERCASE form.
const UUID_A = '11111111-1111-4111-8111-111111111111';
const UUID_B = '22222222-2222-4222-8222-222222222222';

describe('primitives', () => {
  test('ISO8601 round-trips at second precision', () => {
    const d = new Date('2026-05-31T12:34:56.000Z');
    expect(encodeISO8601(d)).toBe('2026-05-31T12:34:56Z');
    expect(decodeISO8601('2026-05-31T12:34:56Z').getTime()).toBe(d.getTime());
  });

  test('ISO8601 strips milliseconds (Swift .iso8601 has second precision)', () => {
    const d = new Date('2026-05-31T12:34:56.789Z');
    expect(encodeISO8601(d)).toBe('2026-05-31T12:34:56Z');
  });

  test('encodeISO8601 throws on invalid Date', () => {
    expect(() => encodeISO8601(new Date('not-a-date'))).toThrow();
  });

  test('decodeISO8601 throws on garbage', () => {
    expect(() => decodeISO8601('nope')).toThrow();
    expect(() => decodeISO8601(42 as unknown)).toThrow();
  });

  test('UUID decode normalises to uppercase, encode matches', () => {
    expect(decodeUUID(UUID_A.toLowerCase())).toBe(UUID_A);
    expect(() => decodeUUID('not-a-uuid')).toThrow();
  });

  test('randomUUID produces a valid v4 UUID', () => {
    const id = randomUUID();
    expect(decodeUUID(id)).toBe(id);
    expect(id[14]).toBe('4');
  });

  test('base64 round-trips arbitrary bytes including empty + padding cases', () => {
    for (const len of [0, 1, 2, 3, 4, 5, 16, 17, 255]) {
      const bytes = new Uint8Array(len);
      for (let i = 0; i < len; i++) bytes[i] = (i * 37 + 11) & 0xff;
      const b64 = encodeBase64(bytes);
      expect(Array.from(decodeBase64(b64))).toEqual(Array.from(bytes));
    }
  });

  test('base64 matches a known vector ("hello")', () => {
    const hello = new Uint8Array([104, 101, 108, 108, 111]);
    expect(encodeBase64(hello)).toBe('aGVsbG8=');
    expect(Array.from(decodeBase64('aGVsbG8='))).toEqual(Array.from(hello));
  });

  test('decodeBase64 rejects bad length + characters', () => {
    expect(() => decodeBase64('abc')).toThrow();
    expect(() => decodeBase64('!!!!')).toThrow();
    expect(() => decodeBase64(123 as unknown)).toThrow();
  });

  test('decodeBase64 rejects an invalid char in the 3rd/4th quad position', () => {
    // First two chars are valid; the third is not a base64 char and not "=".
    expect(() => decodeBase64('aa!=')).toThrow(/Invalid base64 character/);
    expect(() => decodeBase64('aaa!')).toThrow(/Invalid base64 character/);
  });

  test('randomUUID throws when no CSPRNG is available', () => {
    const original = (globalThis as { crypto?: unknown }).crypto;
    delete (globalThis as { crypto?: unknown }).crypto;
    try {
      expect(() => randomUUID()).toThrow(/CSPRNG/);
    } finally {
      if (original !== undefined) {
        (globalThis as { crypto?: unknown }).crypto = original;
      }
    }
  });

  test('randomUUID uses the platform CSPRNG (no Math.random)', () => {
    const spy = jest.spyOn(globalThis.crypto, 'getRandomValues');
    const id = randomUUID();
    expect(spy).toHaveBeenCalledTimes(1);
    expect(decodeUUID(id)).toBe(id);
    spy.mockRestore();
  });
});

describe('primitive field readers reject malformed objects', () => {
  test('asObject rejects non-objects', () => {
    expect(() => asObject(null)).toThrow(/JSON object/);
    expect(() => asObject([1, 2])).toThrow(/JSON object/);
    expect(() => asObject(7 as unknown)).toThrow(/JSON object/);
  });

  test('reqString / reqInt / reqBool / reqArray throw named errors', () => {
    expect(() => reqString({}, 'k')).toThrow(/"k"/);
    expect(() => reqInt({ k: 'x' }, 'k')).toThrow(/"k"/);
    expect(() => reqInt({ k: Infinity }, 'k')).toThrow(/"k"/);
    expect(() => reqBool({ k: 1 }, 'k')).toThrow(/"k"/);
    expect(() => reqArray({ k: {} }, 'k')).toThrow(/"k"/);
  });

  test('optInt returns undefined for null/absent but throws on bad type', () => {
    expect(optInt({}, 'k')).toBeUndefined();
    expect(optInt({ k: null }, 'k')).toBeUndefined();
    expect(optInt({ k: 5 }, 'k')).toBe(5);
    expect(() => optInt({ k: 'x' }, 'k')).toThrow(/"k"/);
  });

  test('reqNumber aliases reqInt', () => {
    expect(reqNumber({ k: 3.5 }, 'k')).toBe(3.5);
    expect(() => reqNumber({}, 'k')).toThrow(/"k"/);
  });

  test('optString returns undefined for null/absent but throws on bad type', () => {
    expect(optString({}, 'k')).toBeUndefined();
    expect(optString({ k: null }, 'k')).toBeUndefined();
    expect(optString({ k: 'v' }, 'k')).toBe('v');
    expect(() => optString({ k: 5 }, 'k')).toThrow(/"k"/);
  });

  test('optBool defaults when absent, returns value, and throws on bad type', () => {
    expect(optBool({}, 'k')).toBe(false);
    expect(optBool({}, 'k', true)).toBe(true);
    expect(optBool({ k: true }, 'k')).toBe(true);
    expect(() => optBool({ k: 1 }, 'k')).toThrow(/"k"/);
  });
});

describe('ToolKind', () => {
  test('known tools round-trip to their case name', () => {
    expect(encodeToolKind(decodeToolKind('webFetch'))).toBe('webFetch');
    expect(decodeToolKind('read')).toEqual(tool('read'));
  });

  test('unknown tools round-trip via custom()', () => {
    const t = decodeToolKind('SomeMCPTool__doThing');
    expect(t).toEqual(customTool('SomeMCPTool__doThing'));
    expect(encodeToolKind(t)).toBe('SomeMCPTool__doThing');
  });

  test('non-string ToolKind throws', () => {
    expect(() => decodeToolKind(5 as unknown)).toThrow();
  });
});

function roundTripClient(msg: ClientMessage): ClientMessage {
  return decodeClientMessage(encodeClientMessage(msg));
}

describe('ClientMessage codec', () => {
  const cases: ClientMessage[] = [
    { type: 'list_sessions' },
    { type: 'create_session', name: 'claude', shell: '/bin/zsh', cwd: '~/p' },
    { type: 'create_session', name: 'bare', shell: '/bin/bash' },
    { type: 'attach_session', sessionId: UUID_A },
    { type: 'input', sessionId: UUID_A, data: 'ls\n' },
    { type: 'resize', sessionId: UUID_A, cols: 120, rows: 40 },
    { type: 'close_session', sessionId: UUID_A },
    { type: 'upload_file', uploadId: UUID_B, filename: 'a.txt', data: 'aGk=' },
    { type: 'list_directory', requestId: UUID_A },
    { type: 'list_directory', requestId: UUID_A, path: '~/foo' },
    { type: 'index_project', requestId: UUID_A, path: '/x', refresh: true },
    { type: 'git_status', requestId: UUID_A, path: '/repo' },
    { type: 'git_diff', requestId: UUID_A, path: '/r', file: 'f.ts', staged: true },
    { type: 'create_agent_session', name: 'c', provider: 'claudeCode' },
    { type: 'create_agent_session', name: 'c', provider: 'codex', cwd: '/x' },
    { type: 'switch_session_mode', sessionId: UUID_A, mode: 'chat' },
    { type: 'agent_input', sessionId: UUID_A, text: 'hi' },
    { type: 'permission_response', sessionId: UUID_A, requestId: UUID_B, allowed: true },
  ];

  test.each(cases.map((c) => [c.type, c] as const))(
    'round-trips %s',
    (_label, msg) => {
      expect(roundTripClient(msg)).toEqual(msg);
    },
  );

  test('wire shape is snake_case type + flat camelCase siblings', () => {
    const wire = encodeClientMessage({
      type: 'git_diff',
      requestId: UUID_A,
      path: '/r',
      file: 'f.ts',
      staged: false,
    });
    expect(wire).toEqual({
      type: 'git_diff',
      requestId: UUID_A,
      path: '/r',
      file: 'f.ts',
      staged: false,
    });
  });

  test('optional cwd is omitted from the wire when absent (encodeIfPresent)', () => {
    const wire = encodeClientMessage({ type: 'create_session', name: 'x', shell: 's' });
    expect('cwd' in wire).toBe(false);
  });

  test('refresh/staged default to false when absent on decode', () => {
    expect(decodeClientMessage({ type: 'index_project', requestId: UUID_A, path: '/x' })).toEqual({
      type: 'index_project',
      requestId: UUID_A,
      path: '/x',
      refresh: false,
    });
  });

  test('string boundary round-trips', () => {
    const msg: ClientMessage = { type: 'agent_input', sessionId: UUID_A, text: 'hello' };
    expect(decodeClientMessageFromString(encodeClientMessageToString(msg))).toEqual(msg);
  });

  test('unknown discriminator throws', () => {
    expect(() => decodeClientMessage({ type: 'nope' })).toThrow();
  });

  test('non-string type throws a named error', () => {
    expect(() => decodeClientMessage({ type: 42 })).toThrow(
      /ClientMessage is missing string "type"/,
    );
  });

  test('server discriminator is rejected by ClientMessage', () => {
    expect(() => decodeClientMessage({ type: 'output', sessionId: UUID_A, data: 'x' })).toThrow();
  });

  test('malformed JSON string throws', () => {
    expect(() => decodeClientMessageFromString('{not json')).toThrow();
  });

  test('missing required field throws', () => {
    expect(() => decodeClientMessage({ type: 'create_session', name: 'x' })).toThrow();
  });

  test('unknown provider throws', () => {
    expect(() =>
      decodeClientMessage({ type: 'create_agent_session', name: 'x', provider: 'bogus' }),
    ).toThrow();
  });

  test('unknown mode throws', () => {
    expect(() =>
      decodeClientMessage({ type: 'switch_session_mode', sessionId: UUID_A, mode: 'bogus' }),
    ).toThrow();
  });
});

function roundTripServer(msg: ServerMessage): ServerMessage {
  return decodeServerMessage(encodeServerMessage(msg));
}

describe('ServerMessage codec', () => {
  const now = new Date('2026-05-31T00:00:00Z');
  const session = {
    id: UUID_A,
    name: 's',
    shell: '/bin/zsh',
    createdAt: now,
  };
  const agentSession = {
    ...session,
    agentProvider: 'claudeCode' as const,
    sessionMode: 'chat' as const,
  };

  const cases: ServerMessage[] = [
    { type: 'session_list', sessions: [session, agentSession] },
    { type: 'session_created', session },
    { type: 'output', sessionId: UUID_A, data: 'aGk=' },
    { type: 'scrollback', sessionId: UUID_A, data: 'aGk=' },
    { type: 'session_closed', sessionId: UUID_A },
    { type: 'error', message: 'boom' },
    { type: 'file_uploaded', uploadId: UUID_B, path: '/tmp/a' },
    { type: 'file_upload_failed', uploadId: UUID_B, message: 'no' },
    {
      type: 'directory_listing',
      requestId: UUID_A,
      path: '/x',
      entries: [{ name: 'a', isDirectory: true, isHidden: false }],
    },
    { type: 'directory_listing_failed', requestId: UUID_A, message: 'no' },
    {
      type: 'index_chunk',
      requestId: UUID_A,
      root: '/x',
      entries: [{ path: 'a/b.ts', isDirectory: false, size: 42 }],
      complete: true,
    },
    {
      type: 'index_chunk',
      requestId: UUID_A,
      root: '/x',
      entries: [{ path: 'dir', isDirectory: true }],
      complete: false,
    },
    { type: 'index_failed', requestId: UUID_A, message: 'no' },
    {
      type: 'git_status_result',
      requestId: UUID_A,
      status: {
        isRepo: true,
        branch: 'main',
        ahead: 1,
        behind: 2,
        files: [{ path: 'a.ts', status: 'M', staged: false }],
      },
    },
    {
      type: 'git_status_result',
      requestId: UUID_A,
      status: { isRepo: false, ahead: 0, behind: 0, files: [] },
    },
    { type: 'git_status_failed', requestId: UUID_A, message: 'no' },
    { type: 'git_diff_result', requestId: UUID_A, file: 'f', diff: 'd', truncated: false },
    { type: 'git_diff_failed', requestId: UUID_A, message: 'no' },
    { type: 'agent_session_created', session: agentSession },
  ];

  test.each(cases.map((c) => [c.type, c] as const))(
    'round-trips %s',
    (_label, msg) => {
      expect(roundTripServer(msg)).toEqual(msg);
    },
  );

  test('SessionInfo keys are camelCase + ISO8601 + UPPERCASE UUID', () => {
    const wire = encodeServerMessage({ type: 'session_created', session: agentSession }) as {
      session: Record<string, unknown>;
    };
    expect(wire.session).toEqual({
      id: UUID_A,
      name: 's',
      shell: '/bin/zsh',
      createdAt: '2026-05-31T00:00:00Z',
      agentProvider: 'claudeCode',
      sessionMode: 'chat',
    });
  });

  test('GitStatus omits the branch key when absent (Swift encodeIfPresent)', () => {
    const wire = encodeServerMessage({
      type: 'git_status_result',
      requestId: UUID_A,
      status: { isRepo: false, ahead: 0, behind: 0, files: [] },
    }) as { status: Record<string, unknown> };
    expect('branch' in wire.status).toBe(false);
  });

  test('GitStatus emits the branch key when present', () => {
    const wire = encodeServerMessage({
      type: 'git_status_result',
      requestId: UUID_A,
      status: { isRepo: true, branch: 'main', ahead: 0, behind: 0, files: [] },
    }) as { status: Record<string, unknown> };
    expect(wire.status.branch).toBe('main');
  });

  test('complete/truncated default to false when absent', () => {
    const decoded = decodeServerMessage({
      type: 'index_chunk',
      requestId: UUID_A,
      root: '/x',
      entries: [],
    });
    expect(decoded).toMatchObject({ complete: false });
  });

  test('string boundary round-trips agent_event', () => {
    const msg: ServerMessage = {
      type: 'agent_event',
      sessionId: UUID_A,
      event: { type: 'assistant_message', text: 'hi' },
    };
    expect(decodeServerMessageFromString(encodeServerMessageToString(msg))).toEqual(msg);
  });

  test('nested agent_event preserves two-level wrapping on the wire', () => {
    const msg: ServerMessage = {
      type: 'agent_event',
      sessionId: UUID_A,
      event: {
        type: 'tool_call_complete',
        event: { id: 'x', tool: tool('bash'), inputSummary: 's', durationMs: 10 },
      },
    };
    const wire = encodeServerMessage(msg) as {
      type: string;
      sessionId: string;
      event: { type: string; event: Record<string, unknown> };
    };
    expect(wire.type).toBe('agent_event');
    expect(wire.event.type).toBe('tool_call_complete');
    expect(wire.event.event).toEqual({
      id: 'x',
      tool: 'bash',
      inputSummary: 's',
      durationMs: 10,
    });
    expect(decodeServerMessage(wire)).toEqual(msg);
  });

  test('unknown discriminator throws', () => {
    expect(() => decodeServerMessage({ type: 'nope' })).toThrow();
  });

  test('non-string type throws a named error', () => {
    expect(() => decodeServerMessage({ type: 42 })).toThrow(
      /ServerMessage is missing string "type"/,
    );
  });

  test('malformed JSON string throws', () => {
    expect(() => decodeServerMessageFromString('nope')).toThrow();
  });

  test('SessionInfo with unknown provider throws', () => {
    expect(() =>
      decodeServerMessage({
        type: 'session_created',
        session: { id: UUID_A, name: 's', shell: 'z', createdAt: '2026-05-31T00:00:00Z', agentProvider: 'x' },
      }),
    ).toThrow();
  });

  test('SessionInfo with unknown sessionMode throws', () => {
    expect(() =>
      decodeServerMessage({
        type: 'session_created',
        session: {
          id: UUID_A,
          name: 's',
          shell: 'z',
          createdAt: '2026-05-31T00:00:00Z',
          sessionMode: 'bogus',
        },
      }),
    ).toThrow(/Unknown sessionMode/);
  });

  test('ToolCallEvent with unknown effort throws', () => {
    expect(() =>
      decodeAgentEvent({
        type: 'tool_call_start',
        event: { id: 'x', tool: 'bash', inputSummary: 's', effort: 'ludicrous' },
      }),
    ).toThrow(/Unknown effort/);
  });
});

function roundTripEvent(ev: AgentEvent): AgentEvent {
  return decodeAgentEvent(encodeAgentEvent(ev));
}

describe('AgentEvent codec', () => {
  const toolEvent = {
    id: 't1',
    tool: tool('bash'),
    inputSummary: 'ls -la',
    result: 'ok',
    durationMs: 12,
    fileDiffs: [{ path: 'a.ts', added: 3, removed: 1 }],
    effort: 'high' as const,
  };

  const cases: AgentEvent[] = [
    { type: 'session_start', id: 's', provider: 'claudeCode', cwd: '/x', source: 'startup' },
    { type: 'session_start', id: 's', provider: 'codex', cwd: '/x', model: 'gpt', source: 'resume' },
    { type: 'session_end', reason: 'logout' },
    { type: 'cwd_changed', from: '/a', to: '/b' },
    { type: 'user_message', text: 'hi' },
    { type: 'token_delta', text: 'he' },
    { type: 'assistant_message', text: 'hello' },
    { type: 'tool_call_start', event: { id: 'x', tool: tool('read'), inputSummary: 'f' } },
    { type: 'tool_call_complete', event: toolEvent },
    { type: 'tool_call_failed', event: { id: 'x', tool: customTool('Custom'), inputSummary: 's', error: 'e' } },
    { type: 'tool_batch_complete', events: [toolEvent, { id: 'y', tool: tool('grep'), inputSummary: 'q' }] },
    {
      type: 'permission_request',
      permissionEvent: { requestId: 'r1', tool: 'bash', inputSummary: 'rm', ruleMatched: 'rule' },
    },
    {
      type: 'permission_request',
      permissionEvent: { requestId: 'r1', tool: 'bash', inputSummary: 'rm' },
    },
    { type: 'permission_denied', tool: 'bash', reason: 'blocked' },
    { type: 'subagent_start', id: 'a', agentType: 'reviewer', parentSessionId: 'p' },
    { type: 'subagent_stop', id: 'a', agentType: 'reviewer' },
    { type: 'task_created', id: 'tk', title: 'Do it' },
    { type: 'task_completed', id: 'tk' },
    { type: 'compaction_started' },
    { type: 'compaction_complete' },
    { type: 'worktree_created', name: 'wt', branch: 'feat/x' },
    { type: 'worktree_removed', path: '/wt' },
    { type: 'notification', notificationType: 'permissionPrompt', message: 'allow?' },
    { type: 'status_badge', text: 'building', kind: 'info' },
    { type: 'session_error', reason: 'rateLimit' },
    { type: 'turn_stop', cost: 0.0123, inputTokens: 100, outputTokens: 200, effortLevel: 'max' },
    { type: 'turn_stop' },
    {
      type: 'elicitation',
      server: 'mcp',
      fields: [{ name: 'k', type: 'string', description: 'd', required: true }],
    },
    { type: 'raw_terminal_bytes', data: new Uint8Array([0, 1, 2, 250, 255]) },
  ];

  test.each(cases.map((c) => [c.type, c] as const))(
    'round-trips %s',
    (_label, ev) => {
      expect(roundTripEvent(ev)).toEqual(ev);
    },
  );

  test('tool_call_* wraps ToolCallEvent under key "event"', () => {
    const wire = encodeAgentEvent({
      type: 'tool_call_start',
      event: { id: 'x', tool: tool('read'), inputSummary: 'f' },
    }) as Record<string, unknown>;
    expect(Object.keys(wire).sort()).toEqual(['event', 'type']);
  });

  test('permission_request wraps under key "permissionEvent"', () => {
    const wire = encodeAgentEvent({
      type: 'permission_request',
      permissionEvent: { requestId: 'r', tool: 'bash', inputSummary: 's' },
    }) as Record<string, unknown>;
    expect('permissionEvent' in wire).toBe(true);
  });

  test('notification uses key "notificationType"', () => {
    const wire = encodeAgentEvent({
      type: 'notification',
      notificationType: 'idlePrompt',
      message: 'm',
    }) as Record<string, unknown>;
    expect(wire.notificationType).toBe('idlePrompt');
  });

  test('raw_terminal_bytes carries base64 under "data"', () => {
    const wire = encodeAgentEvent({
      type: 'raw_terminal_bytes',
      data: new Uint8Array([104, 105]),
    }) as Record<string, unknown>;
    expect(wire.data).toBe('aGk=');
  });

  test('turn_stop omits absent optionals from the wire', () => {
    const wire = encodeAgentEvent({ type: 'turn_stop' }) as Record<string, unknown>;
    expect(Object.keys(wire)).toEqual(['type']);
  });

  test('ToolCallEvent omits absent optionals from the wire', () => {
    const wire = encodeAgentEvent({
      type: 'tool_call_start',
      event: { id: 'x', tool: tool('read'), inputSummary: 'f' },
    }) as { event: Record<string, unknown> };
    expect(Object.keys(wire.event).sort()).toEqual(['id', 'inputSummary', 'tool']);
  });

  test('decode throws on unknown AgentEvent type', () => {
    expect(() => decodeAgentEvent({ type: 'totally_new_event' })).toThrow(
      /Unknown AgentEvent type/,
    );
  });

  test('decode throws on missing string type', () => {
    expect(() => decodeAgentEvent({})).toThrow();
  });

  test('decode throws on unknown nested enum (source)', () => {
    expect(() =>
      decodeAgentEvent({ type: 'session_start', id: 's', provider: 'claudeCode', cwd: '/x', source: 'bad' }),
    ).toThrow();
  });

  test('decode throws on unknown effortLevel', () => {
    expect(() => decodeAgentEvent({ type: 'turn_stop', effortLevel: 'turbo' })).toThrow();
  });

  test('decode throws on bad raw_terminal_bytes base64', () => {
    expect(() => decodeAgentEvent({ type: 'raw_terminal_bytes', data: '!!!' })).toThrow();
  });

  test('tool_call_* throws a named error when "event" is missing', () => {
    for (const type of ['tool_call_start', 'tool_call_complete', 'tool_call_failed']) {
      expect(() => decodeAgentEvent({ type })).toThrow(
        new RegExp(`${type} is missing field "event"`),
      );
    }
  });

  test('tool_batch_complete throws a named error when "events" is missing', () => {
    expect(() => decodeAgentEvent({ type: 'tool_batch_complete' })).toThrow(
      /tool_batch_complete is missing field "events"/,
    );
  });

  test('tool_batch_complete still validates a non-array "events"', () => {
    expect(() =>
      decodeAgentEvent({ type: 'tool_batch_complete', events: 'nope' }),
    ).toThrow();
  });

  test('permission_request throws a named error when "permissionEvent" is missing', () => {
    expect(() => decodeAgentEvent({ type: 'permission_request' })).toThrow(
      /permission_request is missing field "permissionEvent"/,
    );
  });

  test('fileDiffs absent stays absent', () => {
    const ev = roundTripEvent({
      type: 'tool_call_complete',
      event: { id: 'x', tool: tool('edit'), inputSummary: 's' },
    });
    expect(ev).toEqual({
      type: 'tool_call_complete',
      event: { id: 'x', tool: tool('edit'), inputSummary: 's' },
    });
  });
});

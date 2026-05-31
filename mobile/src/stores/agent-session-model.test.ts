import {
  AgentSessionModel,
  AgentChatItem,
  HISTORY_PAGE_SIZE,
  MAX_RESIDENT_PAGES,
} from './agent-session-model';
import { permission, toolCall, uuid } from '@/test/fixtures';
import { AgentEvent, tool } from '@/protocol';

function model(): AgentSessionModel {
  return new AgentSessionModel(uuid(), 'claudeCode', 'chat', '');
}

function kinds(m: AgentSessionModel): string[] {
  return m.items.map((i) => i.kind);
}

describe('AgentSessionModel', () => {
  it('applies session_start and cwd_changed metadata', () => {
    const m = model();
    m.apply({
      type: 'session_start',
      id: 'a',
      provider: 'codex',
      cwd: '/proj',
      model: 'gpt-5',
      source: 'startup',
    });
    expect(m.provider).toBe('codex');
    expect(m.cwd).toBe('/proj');
    expect(m.model).toBe('gpt-5');
    m.apply({ type: 'cwd_changed', from: '/proj', to: '/proj/sub' });
    expect(m.cwd).toBe('/proj/sub');
  });

  it('appends a user bubble', () => {
    const m = model();
    let fired = 0;
    m.subscribe(() => fired++);
    m.apply({ type: 'user_message', text: 'hello' });
    expect(m.items).toHaveLength(1);
    expect(m.items[0]).toMatchObject({ kind: 'user', text: 'hello' });
    expect(fired).toBe(1);
  });

  it('streams token_delta into a single growing assistant bubble', () => {
    const m = model();
    m.apply({ type: 'token_delta', text: 'Hel' });
    m.apply({ type: 'token_delta', text: 'lo' });
    expect(m.items).toHaveLength(1);
    expect(m.items[0]).toMatchObject({
      kind: 'assistant',
      text: 'Hello',
      streaming: true,
    });
  });

  it('starts a new streaming bubble after a non-assistant item interrupts', () => {
    const m = model();
    m.apply({ type: 'token_delta', text: 'a' });
    m.apply({ type: 'user_message', text: 'mid' });
    m.apply({ type: 'token_delta', text: 'b' });
    expect(kinds(m)).toEqual(['assistant', 'user', 'assistant']);
    expect(m.items[2]).toMatchObject({ text: 'b', streaming: true });
  });

  it('finalises streaming bubble on assistant_message', () => {
    const m = model();
    m.apply({ type: 'token_delta', text: 'partial' });
    m.apply({ type: 'assistant_message', text: 'final' });
    expect(kinds(m)).toEqual(['assistant', 'assistant']);
    expect(m.items[0]).toMatchObject({ streaming: false });
    expect(m.items[1]).toMatchObject({ text: 'final', streaming: false });
  });

  it('accumulates tool calls and flushes the batch before a user message', () => {
    const m = model();
    m.apply({ type: 'tool_call_start', event: toolCall({ id: 't1' }) });
    expect(m.isThinking).toBe(true);
    m.apply({ type: 'tool_call_complete', event: toolCall({ id: 't1' }) });
    expect(m.isThinking).toBe(false);
    m.apply({ type: 'tool_call_failed', event: toolCall({ id: 't2', error: 'x' }) });
    m.apply({ type: 'user_message', text: 'next' });
    expect(kinds(m)).toEqual(['toolBatch', 'user']);
    const batch = m.items[0] as Extract<AgentChatItem, { kind: 'toolBatch' }>;
    expect(batch.tools).toHaveLength(2);
  });

  it('keeps thinking while multiple tool calls are in flight', () => {
    const m = model();
    m.apply({ type: 'tool_call_start', event: toolCall({ id: 't1' }) });
    m.apply({ type: 'tool_call_start', event: toolCall({ id: 't2' }) });
    m.apply({ type: 'tool_call_complete', event: toolCall({ id: 't1' }) });
    expect(m.isThinking).toBe(true);
    m.apply({ type: 'tool_call_complete', event: toolCall({ id: 't2' }) });
    expect(m.isThinking).toBe(false);
  });

  it('finalises a streaming bubble before a flushed batch (no interleave)', () => {
    const m = model();
    m.apply({ type: 'token_delta', text: 'thinking…' });
    m.apply({ type: 'tool_call_complete', event: toolCall({ id: 't1' }) });
    m.apply({ type: 'turn_stop', cost: 0.01 });
    expect(kinds(m)).toEqual(['assistant', 'toolBatch', 'turnSummary']);
    expect(m.items[0]).toMatchObject({ streaming: false });
  });

  it('treats tool_batch_complete as server-authoritative', () => {
    const m = model();
    m.apply({ type: 'tool_call_complete', event: toolCall({ id: 'local' }) });
    m.apply({
      type: 'tool_batch_complete',
      events: [toolCall({ id: 's1' }), toolCall({ id: 's2' })],
    });
    expect(kinds(m)).toEqual(['toolBatch']);
    const batch = m.items[0] as Extract<AgentChatItem, { kind: 'toolBatch' }>;
    expect(batch.tools.map((t) => t.id)).toEqual(['s1', 's2']);
    expect(m.isThinking).toBe(false);
  });

  it('toggles a tool-batch collapsed flag', () => {
    const m = model();
    m.apply({ type: 'tool_batch_complete', events: [toolCall()] });
    const id = m.items[0]!.id;
    expect((m.items[0] as { collapsed: boolean }).collapsed).toBe(true);
    m.toggleBatch(id);
    expect((m.items[0] as { collapsed: boolean }).collapsed).toBe(false);
    m.toggleBatch('missing');
    m.apply({ type: 'user_message', text: 'x' });
    m.toggleBatch(m.items[1]!.id); // not a batch → no-op
    expect((m.items[1] as { kind: string }).kind).toBe('user');
  });

  it('handles permission request + resolve', () => {
    const m = model();
    const evt = permission({ requestId: 'r1' });
    m.apply({ type: 'permission_request', permissionEvent: evt });
    expect(m.pendingPermission).toEqual(evt);
    expect(kinds(m)).toEqual(['permission']);
    expect(m.isThinking).toBe(false);
    m.resolvePermission('other');
    expect(m.pendingPermission).toEqual(evt);
    m.resolvePermission('r1');
    expect(m.pendingPermission).toBeNull();
  });

  it('clears pending permission on permission_denied', () => {
    const m = model();
    m.apply({ type: 'permission_request', permissionEvent: permission({ requestId: 'r' }) });
    m.apply({ type: 'permission_denied', tool: 'bash', reason: 'no' });
    expect(m.pendingPermission).toBeNull();
  });

  it('appends a status badge', () => {
    const m = model();
    m.apply({ type: 'status_badge', text: 'Indexing', kind: 'info' });
    expect(m.items[0]).toMatchObject({ kind: 'statusBadge', badge: 'info' });
  });

  it('appends a turn summary only when it carries cost/tokens', () => {
    const m = model();
    m.apply({
      type: 'turn_stop',
      cost: 0.05,
      inputTokens: 100,
      outputTokens: 50,
      effortLevel: 'high',
    });
    expect(m.items[0]).toMatchObject({
      kind: 'turnSummary',
      cost: 0.05,
      inputTokens: 100,
      outputTokens: 50,
      effortLevel: 'high',
    });
  });

  it('does not append an empty turn summary but still notifies', () => {
    const m = model();
    let fired = 0;
    m.subscribe(() => fired++);
    m.apply({ type: 'turn_stop' });
    expect(m.items).toHaveLength(0);
    expect(fired).toBe(1);
  });

  it('appends a session error', () => {
    const m = model();
    m.apply({ type: 'session_error', reason: 'rateLimit' });
    expect(m.items[0]).toMatchObject({ kind: 'sessionError', reason: 'rateLimit' });
  });

  it('finalises on session_end without adding an item', () => {
    const m = model();
    m.apply({ type: 'token_delta', text: 'x' });
    m.apply({ type: 'session_end', reason: 'logout' });
    expect(kinds(m)).toEqual(['assistant']);
    expect(m.items[0]).toMatchObject({ streaming: false });
  });

  it('ignores non-timeline events but still notifies', () => {
    const m = model();
    let fired = 0;
    m.subscribe(() => fired++);
    const ev: AgentEvent = { type: 'compaction_started' };
    m.apply(ev);
    expect(m.items).toHaveLength(0);
    expect(fired).toBe(1);
  });

  it('prepends history at the head and reports nothing prepended for empty', () => {
    const m = model();
    m.apply({ type: 'user_message', text: 'live' });
    const older: AgentChatItem[] = [
      { id: 'o1', kind: 'user', text: 'older' },
    ];
    expect(m.prependHistory(older)).toBe(true);
    expect(m.items[0]).toMatchObject({ text: 'older' });
    expect(m.items[1]).toMatchObject({ text: 'live' });
    expect(m.prependHistory([])).toBe(false);
  });

  it('trims the resident window from the head, keeping the live tail', () => {
    const m = model();
    const total = HISTORY_PAGE_SIZE * MAX_RESIDENT_PAGES + 10;
    for (let i = 0; i < total; i++) {
      m.apply({ type: 'user_message', text: `m${i}` });
    }
    expect(m.items).toHaveLength(HISTORY_PAGE_SIZE * MAX_RESIDENT_PAGES);
    const lastItem = m.items[m.items.length - 1] as { text: string };
    expect(lastItem.text).toBe(`m${total - 1}`);
  });

  it('trims a large prepended history page from the head', () => {
    const m = model();
    m.apply({ type: 'user_message', text: 'tail' });
    const big: AgentChatItem[] = [];
    for (let i = 0; i < HISTORY_PAGE_SIZE * MAX_RESIDENT_PAGES + 5; i++) {
      big.push({ id: `b${i}`, kind: 'user', text: `b${i}` });
    }
    m.prependHistory(big);
    expect(m.items).toHaveLength(HISTORY_PAGE_SIZE * MAX_RESIDENT_PAGES);
    expect((m.items[m.items.length - 1] as { text: string }).text).toBe('tail');
  });

  it('finalises a streaming bubble when a pending batch flushes before the assistant message', () => {
    const m = model();
    m.apply({ type: 'token_delta', text: 'streamed' });
    // A tool batch is pending; assistant_message flushes it (finalising the
    // streaming bubble first) then appends the final assistant message.
    m.apply({ type: 'tool_call_complete', event: toolCall({ id: 't' }) });
    m.apply({ type: 'assistant_message', text: 'done' });
    const streamed = m.items.find(
      (i) => i.kind === 'assistant' && i.text === 'streamed',
    ) as Extract<AgentChatItem, { kind: 'assistant' }>;
    expect(streamed.streaming).toBe(false);
  });

  it('finalises a streaming bubble pushed off the tail by a server batch', () => {
    const m = model();
    m.apply({ type: 'token_delta', text: 'streamed' });
    // A server-authoritative batch appends after the streaming bubble without
    // finalising it, so the bubble is no longer the tail.
    m.apply({ type: 'tool_batch_complete', events: [toolCall()] });
    // turn_stop now finalises via the fallback scan (bubble is at index 0).
    m.apply({ type: 'turn_stop', cost: 0.01 });
    const streamed = m.items.find(
      (i) => i.kind === 'assistant' && i.text === 'streamed',
    ) as Extract<AgentChatItem, { kind: 'assistant' }>;
    expect(streamed.streaming).toBe(false);
  });

  it('renders custom tool names through the batch', () => {
    const m = model();
    m.apply({
      type: 'tool_batch_complete',
      events: [toolCall({ tool: tool('read') })],
    });
    expect((m.items[0] as { tools: unknown[] }).tools).toHaveLength(1);
  });
});

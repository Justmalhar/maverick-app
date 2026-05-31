/**
 * Port of the Swift `AgentSessionModel` + `AgentChatItem`. This is the killer
 * feature's core: it folds the raw `AgentEvent` stream into a render-ready
 * timeline of chat items, preserving every invariant from Swift:
 *
 *   - token_delta appends to the trailing streaming assistant bubble (O(1)
 *     fast path; creates a new bubble if none is active)
 *   - assistant_message finalises any streaming bubble then appends a final one
 *   - tool_call_(start|complete|failed) accumulate into a pending batch; the
 *     batch flushes before the next user/assistant/turn boundary
 *   - tool_batch_complete is server-authoritative and supersedes the local list
 *   - permission_request sets pendingPermission AND appends an inline row
 *   - turn_stop appends a summary only when it carries cost/tokens
 *   - the streaming bubble is finalised before a flushed batch so a tool batch
 *     never interleaves inside an assistant segment
 *
 * History paging (loadAgentHistory): older items prepend at the head;
 * `trimResident` caps resident pages to ~5 (250 items) from the *head* so the
 * bottom-anchored live tail is never dropped.
 */

import {
  AgentEvent,
  AgentProvider,
  BadgeKind,
  EffortLevel,
  PermissionEvent,
  SessionMode,
  StopFailureReason,
  ToolCallEvent,
} from '@/protocol';
import { Observable } from '@/lib/observable';
import { randomUUID } from '@/protocol/primitives';

export type AgentChatItem =
  | { id: string; kind: 'user'; text: string }
  | { id: string; kind: 'assistant'; text: string; streaming: boolean }
  | { id: string; kind: 'toolBatch'; tools: ToolCallEvent[]; collapsed: boolean }
  | { id: string; kind: 'permission'; event: PermissionEvent }
  | { id: string; kind: 'statusBadge'; text: string; badge: BadgeKind }
  | {
      id: string;
      kind: 'turnSummary';
      cost?: number;
      inputTokens?: number;
      outputTokens?: number;
      effortLevel?: EffortLevel;
    }
  | { id: string; kind: 'sessionError'; reason: StopFailureReason };

export const HISTORY_PAGE_SIZE = 50;
export const MAX_RESIDENT_PAGES = 5;
const MAX_RESIDENT_ITEMS = HISTORY_PAGE_SIZE * MAX_RESIDENT_PAGES;

export class AgentSessionModel extends Observable {
  provider: AgentProvider;
  mode: SessionMode;
  cwd: string;
  model?: string;
  isThinking = false;

  private timeline: AgentChatItem[] = [];
  private pending: PermissionEvent | null = null;

  private readonly pendingToolCalls = new Map<string, ToolCallEvent>();
  private completedBatch: ToolCallEvent[] = [];
  private streamingBubbleId: string | null = null;

  constructor(
    readonly sessionId: string,
    provider: AgentProvider,
    mode: SessionMode,
    cwd: string,
  ) {
    super();
    this.provider = provider;
    this.mode = mode;
    this.cwd = cwd;
  }

  get items(): AgentChatItem[] {
    return this.timeline;
  }

  get pendingPermission(): PermissionEvent | null {
    return this.pending;
  }

  /** Called by the UI after the user approves or denies a permission. */
  resolvePermission(requestId: string): void {
    if (this.pending?.requestId === requestId) {
      this.pending = null;
      this.notify();
    }
  }

  /** Toggle a tool-batch row's collapsed state (UI affordance). */
  toggleBatch(itemId: string): void {
    const idx = this.timeline.findIndex((i) => i.id === itemId);
    if (idx < 0) return;
    const item = this.timeline[idx]!;
    if (item.kind !== 'toolBatch') return;
    this.timeline = this.timeline.slice();
    this.timeline[idx] = { ...item, collapsed: !item.collapsed };
    this.notify();
  }

  apply(event: AgentEvent): void {
    switch (event.type) {
      case 'session_start':
        this.provider = event.provider;
        this.cwd = event.cwd;
        this.model = event.model;
        break;
      case 'cwd_changed':
        this.cwd = event.to;
        break;
      case 'user_message':
        this.flushBatch();
        this.push({ id: randomUUID(), kind: 'user', text: event.text });
        break;
      case 'token_delta': {
        this.flushBatch();
        this.isThinking = false;
        const last = this.timeline[this.timeline.length - 1];
        if (
          this.streamingBubbleId !== null &&
          last !== undefined &&
          last.id === this.streamingBubbleId &&
          last.kind === 'assistant'
        ) {
          this.timeline = this.timeline.slice();
          this.timeline[this.timeline.length - 1] = {
            ...last,
            text: last.text + event.text,
            streaming: true,
          };
        } else {
          const id = randomUUID();
          this.streamingBubbleId = id;
          this.push({ id, kind: 'assistant', text: event.text, streaming: true });
        }
        break;
      }
      case 'assistant_message':
        this.flushBatch();
        this.finalizeStreamingBubble();
        this.push({
          id: randomUUID(),
          kind: 'assistant',
          text: event.text,
          streaming: false,
        });
        break;
      case 'tool_call_start':
        this.isThinking = true;
        this.pendingToolCalls.set(event.event.id, event.event);
        break;
      case 'tool_call_complete':
      case 'tool_call_failed':
        this.pendingToolCalls.delete(event.event.id);
        this.completedBatch.push(event.event);
        if (this.pendingToolCalls.size === 0) this.isThinking = false;
        this.notify();
        break;
      case 'tool_batch_complete':
        this.completedBatch = [];
        this.pendingToolCalls.clear();
        this.push({
          id: randomUUID(),
          kind: 'toolBatch',
          tools: event.events,
          collapsed: true,
        });
        this.isThinking = false;
        break;
      case 'permission_request':
        this.pending = event.permissionEvent;
        this.push({
          id: randomUUID(),
          kind: 'permission',
          event: event.permissionEvent,
        });
        this.isThinking = false;
        break;
      case 'permission_denied':
        this.pending = null;
        this.notify();
        break;
      case 'status_badge':
        this.push({
          id: randomUUID(),
          kind: 'statusBadge',
          text: event.text,
          badge: event.kind,
        });
        break;
      case 'turn_stop':
        this.flushBatch();
        this.finalizeStreamingBubble();
        this.isThinking = false;
        if (
          event.cost !== undefined ||
          event.inputTokens !== undefined ||
          event.outputTokens !== undefined
        ) {
          const item: AgentChatItem = {
            id: randomUUID(),
            kind: 'turnSummary',
          };
          if (event.cost !== undefined) item.cost = event.cost;
          if (event.inputTokens !== undefined) item.inputTokens = event.inputTokens;
          if (event.outputTokens !== undefined) {
            item.outputTokens = event.outputTokens;
          }
          if (event.effortLevel !== undefined) item.effortLevel = event.effortLevel;
          this.push(item);
        } else {
          this.notify();
        }
        break;
      case 'session_error':
        this.flushBatch();
        this.finalizeStreamingBubble();
        this.isThinking = false;
        this.push({
          id: randomUUID(),
          kind: 'sessionError',
          reason: event.reason,
        });
        break;
      case 'session_end':
        this.flushBatch();
        this.finalizeStreamingBubble();
        this.isThinking = false;
        this.notify();
        break;
      default:
        // subagent/task/compaction/worktree/notification/elicitation/raw bytes
        // do not contribute chat items in the mobile timeline.
        this.notify();
        break;
    }
  }

  /**
   * Prepend a page of older, already-reduced items at the head (bottom-anchored
   * paging). Returns true if anything was prepended. Trims from the head if the
   * resident window exceeds MAX_RESIDENT_ITEMS.
   */
  prependHistory(older: AgentChatItem[]): boolean {
    if (older.length === 0) return false;
    this.timeline = [...older, ...this.timeline];
    this.trimResident();
    this.notify();
    return true;
  }

  private trimResident(): void {
    if (this.timeline.length > MAX_RESIDENT_ITEMS) {
      this.timeline = this.timeline.slice(
        this.timeline.length - MAX_RESIDENT_ITEMS,
      );
    }
  }

  private push(item: AgentChatItem): void {
    this.timeline = [...this.timeline, item];
    this.trimResident();
    this.notify();
  }

  private flushBatch(): void {
    if (this.completedBatch.length === 0) return;
    if (this.streamingBubbleId !== null) this.finalizeStreamingBubble();
    const batch = this.completedBatch;
    this.completedBatch = [];
    this.timeline = [
      ...this.timeline,
      { id: randomUUID(), kind: 'toolBatch', tools: batch, collapsed: true },
    ];
    this.trimResident();
  }

  private finalizeStreamingBubble(): void {
    const sid = this.streamingBubbleId;
    if (sid === null) return;
    this.streamingBubbleId = null;
    const last = this.timeline[this.timeline.length - 1];
    if (last !== undefined && last.id === sid && last.kind === 'assistant') {
      this.timeline = this.timeline.slice();
      this.timeline[this.timeline.length - 1] = { ...last, streaming: false };
      return;
    }
    // Fallback: the streaming bubble was pushed off the tail (a server
    // tool_batch_complete appends directly without finalising stream first).
    const idx = this.timeline.findIndex((i) => i.id === sid);
    /* istanbul ignore else -- the id always points at the assistant bubble we
       created; the guard is defensive. */
    if (idx >= 0) {
      const item = this.timeline[idx]!;
      /* istanbul ignore else -- same invariant: the item at sid is assistant. */
      if (item.kind === 'assistant') {
        this.timeline = this.timeline.slice();
        this.timeline[idx] = { ...item, streaming: false };
      }
    }
  }
}

/**
 * Trust-On-First-Use pinning for the desktop's static public key.
 *
 * On the first successful pairing with a node we pin its static X25519 key. On
 * every subsequent connection we assert the presented key matches the pin; a
 * mismatch means a different/spoofed desktop is answering and MUST abort
 * (classic MITM defence). The store is an injectable interface so RN-2 can back
 * it with expo-secure-store while tests use the in-memory implementation.
 */

import { bytesToBase64url } from './base64url';

export interface PinRecord {
  nodeId: string;
  staticPublicKey: Uint8Array;
  pinnedAt: number;
}

export interface PinStorage {
  load(nodeId: string): PinRecord | undefined;
  save(record: PinRecord): void;
  remove(nodeId: string): void;
}

export class InMemoryPinStorage implements PinStorage {
  private readonly map = new Map<string, PinRecord>();

  load(nodeId: string): PinRecord | undefined {
    return this.map.get(nodeId);
  }

  save(record: PinRecord): void {
    this.map.set(record.nodeId, record);
  }

  remove(nodeId: string): void {
    this.map.delete(nodeId);
  }
}

export class TofuMismatchError extends Error {
  constructor(
    public readonly nodeId: string,
    public readonly expected: string,
    public readonly actual: string,
  ) {
    super(`TOFU key mismatch for node "${nodeId}"`);
    this.name = 'TofuMismatchError';
  }
}

function constantTimeEqual(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i]! ^ b[i]!;
  return diff === 0;
}

export class TofuPinner {
  constructor(private readonly storage: PinStorage) {}

  /**
   * Verify a presented static key against the pin for `nodeId`. On first sight
   * it pins and returns `{ firstUse: true }`; on a match it returns
   * `{ firstUse: false }`; on a mismatch it throws `TofuMismatchError`.
   */
  verify(
    nodeId: string,
    staticPublicKey: Uint8Array,
  ): { firstUse: boolean } {
    const existing = this.storage.load(nodeId);
    if (!existing) {
      this.storage.save({ nodeId, staticPublicKey, pinnedAt: Date.now() });
      return { firstUse: true };
    }
    if (!constantTimeEqual(existing.staticPublicKey, staticPublicKey)) {
      throw new TofuMismatchError(
        nodeId,
        bytesToBase64url(existing.staticPublicKey),
        bytesToBase64url(staticPublicKey),
      );
    }
    return { firstUse: false };
  }

  pinned(nodeId: string): PinRecord | undefined {
    return this.storage.load(nodeId);
  }

  unpin(nodeId: string): void {
    this.storage.remove(nodeId);
  }
}

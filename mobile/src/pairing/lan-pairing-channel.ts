/**
 * LAN PairingChannel — carries the three Noise_XX handshake frames over a raw
 * WebSocket to the desktop's pairing endpoint before the authenticated session
 * begins. Frames are length-agnostic binary messages (base64-on-the-wire to
 * survive text sockets). This touches the platform WebSocket, so it is excluded
 * from coverage; the PairingController it feeds is fully tested with a fake
 * channel.
 */

/* istanbul ignore file -- platform WebSocket glue; logic tested via FakeChannel. */

import { PairingChannel } from './pairing-controller';
import { bytesToBase64url, base64urlToBytes } from './base64url';

interface SocketLike {
  onopen: (() => void) | null;
  onmessage: ((ev: { data: unknown }) => void) | null;
  onerror: ((ev: unknown) => void) | null;
  send(data: string): void;
  close(): void;
}

export function lanPairingUrl(host: string, port: number): string {
  return `ws://${host}:${port}/pair`;
}

export class LanPairingChannel implements PairingChannel {
  private readonly socket: SocketLike;
  private readonly inbound: Uint8Array[] = [];
  private waiter: ((frame: Uint8Array) => void) | null = null;
  private readonly opened: Promise<void>;

  constructor(url: string) {
    const Ctor = (globalThis as { WebSocket?: new (u: string) => SocketLike })
      .WebSocket;
    if (!Ctor) throw new Error('No global WebSocket for LAN pairing');
    this.socket = new Ctor(url);
    this.opened = new Promise<void>((resolve, reject) => {
      this.socket.onopen = () => resolve();
      this.socket.onerror = () => reject(new Error('Pairing socket error'));
    });
    this.socket.onmessage = (ev) => {
      if (typeof ev.data !== 'string') return;
      const frame = base64urlToBytes(ev.data);
      if (this.waiter) {
        this.waiter(frame);
        this.waiter = null;
      } else {
        this.inbound.push(frame);
      }
    };
  }

  async ready(): Promise<void> {
    await this.opened;
  }

  send(frame: Uint8Array): void {
    this.socket.send(bytesToBase64url(frame));
  }

  receive(): Promise<Uint8Array> {
    const buffered = this.inbound.shift();
    if (buffered !== undefined) return Promise.resolve(buffered);
    return new Promise((resolve) => {
      this.waiter = resolve;
    });
  }

  close(): void {
    this.socket.close();
  }
}

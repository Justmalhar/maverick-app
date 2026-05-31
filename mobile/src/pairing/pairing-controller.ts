/**
 * Drives the device-pairing flow as an observable state machine for the QR
 * scan screen. Stages:
 *
 *   idle → parsing → handshaking → verify (TOFU safety-number shown) → paired
 *                                                          ↘ error (any failure)
 *
 * The three Noise_XX messages are pumped over an injected `PairingChannel`
 * (LAN now; iroh/relay later), so the controller is transport-agnostic and unit
 * testable with a fake channel. On success it records the host in the supplied
 * `ConnectionHistory` (with the pinned key fingerprint) so the device persists.
 */

import { Observable } from '@/lib/observable';
import { ConnectionHistory } from '@/app/connection-history';
import { bytesToBase64url } from './base64url';
import { InitiatorPairingSession, PairingResult } from './pairing-session';
import { parsePairingPayload, PairingPayload } from './qr-payload';
import { safetyNumber } from './safety-number';
import { TofuPinner } from './tofu-store';

export type PairingStage =
  | 'idle'
  | 'parsing'
  | 'handshaking'
  | 'verify'
  | 'paired'
  | 'error';

/** Minimal duplex byte channel for the three handshake frames. */
export interface PairingChannel {
  send(frame: Uint8Array): void;
  /** Resolves with the next inbound frame. */
  receive(): Promise<Uint8Array>;
  close(): void;
}

export interface PairResult {
  payload: PairingPayload;
  result: PairingResult;
  safetyNumber: string;
}

export class PairingController extends Observable {
  private currentStage: PairingStage = 'idle';
  private errorMessage: string | null = null;
  private currentSafetyNumber: string | null = null;
  private result: PairResult | null = null;

  constructor(
    private readonly pinner: TofuPinner,
    private readonly history: ConnectionHistory,
  ) {
    super();
  }

  get stage(): PairingStage {
    return this.currentStage;
  }
  get error(): string | null {
    return this.errorMessage;
  }
  get safetyNumber(): string | null {
    return this.currentSafetyNumber;
  }
  get pairResult(): PairResult | null {
    return this.result;
  }

  reset(): void {
    this.currentStage = 'idle';
    this.errorMessage = null;
    this.currentSafetyNumber = null;
    this.result = null;
    this.notify();
  }

  /**
   * Parse a scanned QR string and run the handshake over `channel`. On success
   * the controller lands in `verify` with a safety-number to confirm; the
   * caller then calls `confirm(...)` to persist or `reset()` to abort.
   */
  async pair(qr: string, channel: PairingChannel): Promise<void> {
    this.setStage('parsing');
    let payload: PairingPayload;
    try {
      payload = parsePairingPayload(qr);
    } catch (e) {
      this.fail((e as Error).message);
      return;
    }

    this.setStage('handshaking');
    try {
      const session = new InitiatorPairingSession(payload, this.pinner);
      channel.send(session.start());
      const message2 = await channel.receive();
      const message3 = session.handleMessage2(message2);
      channel.send(message3);
      const result = session.complete();
      this.result = {
        payload,
        result,
        safetyNumber: safetyNumber(result.remoteStaticPublicKey),
      };
      this.currentSafetyNumber = this.result.safetyNumber;
      this.setStage('verify');
    } catch (e) {
      this.fail((e as Error).message);
    } finally {
      channel.close();
    }
  }

  /**
   * Confirm the verified safety-number and persist the device. `host`/`port`
   * come from the scan context (relay hint or manual fallback).
   */
  confirm(host: string, port: number): void {
    if (this.result === null) {
      this.fail('No pairing result to confirm');
      return;
    }
    const opts: { name?: string; token?: string; pinnedKey: string } = {
      pinnedKey: bytesToBase64url(this.result.result.remoteStaticPublicKey),
    };
    if (this.result.payload.name !== undefined) opts.name = this.result.payload.name;
    // The QR parser guarantees a non-empty token, so it always persists.
    opts.token = this.result.payload.token;
    this.history.record(host, port, opts);
    this.setStage('paired');
  }

  private setStage(stage: PairingStage): void {
    this.currentStage = stage;
    this.errorMessage = null;
    this.notify();
  }

  private fail(message: string): void {
    this.currentStage = 'error';
    this.errorMessage = message;
    this.notify();
  }
}

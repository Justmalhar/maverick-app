/**
 * High-level pairing orchestration for the mobile client (initiator). Glues:
 *   1. QR payload parse (PairingPayload)
 *   2. Noise_XX handshake (this side = initiator)
 *   3. TOFU verification of the desktop's static key once learned
 *
 * The transport that carries the three handshake messages is supplied by the
 * caller (LAN now; iroh/relay later) — pairing itself is transport-agnostic and
 * yields transport-independent session keys.
 */

import { bytesEqual, KeyPair } from './noise-crypto';
import { NoiseXX, TransportKeys } from './noise-xx';
import { PairingPayload } from './qr-payload';
import { TofuPinner } from './tofu-store';

export interface PairingResult {
  keys: TransportKeys;
  remoteStaticPublicKey: Uint8Array;
  firstUse: boolean;
}

export class PairingError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'PairingError';
  }
}

/**
 * Drives the initiator side of a paired handshake. Caller pumps the three
 * messages over a transport:
 *
 *   const session = new InitiatorPairingSession(payload, pinner);
 *   const msg1 = session.start();          // send to desktop
 *   const msg3 = session.handleMessage2(received2); // send to desktop
 *   const result = session.complete();     // derive keys + TOFU verify
 */
export class InitiatorPairingSession {
  private readonly noise: NoiseXX;
  private started = false;
  private completed = false;

  constructor(
    private readonly payload: PairingPayload,
    private readonly pinner: TofuPinner,
    private readonly nodeId: string = payload.name ?? 'default',
    staticKeyPair?: KeyPair,
  ) {
    this.noise = NoiseXX.initiator(
      staticKeyPair ? { staticKeyPair } : {},
    );
  }

  /** Message 1 (`-> e`). The pairing token rides as the handshake payload. */
  start(): Uint8Array {
    if (this.started) throw new PairingError('Pairing already started');
    this.started = true;
    return this.noise.writeMessage(new TextEncoder().encode(this.payload.token));
  }

  /** Consume message 2 (`<- e, ee, s, es`) and produce message 3 (`-> s, se`). */
  handleMessage2(message2: Uint8Array): Uint8Array {
    if (!this.started) throw new PairingError('Pairing not started');
    this.noise.readMessage(message2);

    const learned = this.noise.remoteStaticPublicKey;
    /* istanbul ignore next -- readMessage(msg2) always decrypts + sets `rs`
       (it throws earlier on tamper), so `learned` is non-null here. */
    if (!learned) {
      throw new PairingError('Did not learn desktop static key from message 2');
    }
    // The QR-advertised static key must match what the handshake produced;
    // otherwise the responder is not the device that printed the QR code.
    if (!bytesEqual(learned, this.payload.staticPublicKey)) {
      throw new PairingError(
        'Desktop static key does not match the scanned QR code',
      );
    }
    return this.noise.writeMessage();
  }

  /** Finalise: derive transport keys and apply TOFU pinning. */
  complete(): PairingResult {
    if (this.completed) throw new PairingError('Pairing already completed');
    if (!this.noise.complete) {
      throw new PairingError('Handshake not complete');
    }
    this.completed = true;
    const remoteStaticPublicKey = this.noise.remoteStaticPublicKey!;
    const { firstUse } = this.pinner.verify(this.nodeId, remoteStaticPublicKey);
    return {
      keys: this.noise.finalize(),
      remoteStaticPublicKey,
      firstUse,
    };
  }

  get staticPublicKey(): Uint8Array {
    return this.noise.staticPublicKey;
  }
}

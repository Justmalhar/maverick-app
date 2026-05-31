import {
  PairingChannel,
  PairingController,
} from './pairing-controller';
import { ConnectionHistory } from '@/app/connection-history';
import { MemoryStore } from '@/app/storage';
import { InMemoryPinStorage, TofuPinner } from './tofu-store';
import { bytesToBase64url } from './base64url';
import { generateKeyPair } from './noise-crypto';
import { NoiseXX } from './noise-xx';

/**
 * A channel that drives a real Noise_XX responder. The controller (initiator)
 * sends msg1 → we reply with msg2; it sends msg3 → handshake completes.
 */
class ResponderChannel implements PairingChannel {
  closed = false;
  private readonly responder: NoiseXX;
  private resolveMsg2: ((m: Uint8Array) => void) | null = null;
  private buffered2: Uint8Array | null = null;

  constructor(staticKeyPair: { publicKey: Uint8Array; privateKey: Uint8Array }) {
    this.responder = NoiseXX.responder({ staticKeyPair });
  }

  send(frame: Uint8Array): void {
    if (this.responder.role === 'responder' && !this.responder.complete) {
      try {
        this.responder.readMessage(frame); // msg1 then msg3
      } catch {
        return;
      }
      if (this.responder.complete) return;
      const msg2 = this.responder.writeMessage();
      if (this.resolveMsg2) {
        this.resolveMsg2(msg2);
        this.resolveMsg2 = null;
      } else {
        this.buffered2 = msg2;
      }
    }
  }

  receive(): Promise<Uint8Array> {
    if (this.buffered2) {
      const m = this.buffered2;
      this.buffered2 = null;
      return Promise.resolve(m);
    }
    return new Promise((resolve) => {
      this.resolveMsg2 = resolve;
    });
  }

  close(): void {
    this.closed = true;
  }
}

/** A channel whose receive() rejects, to exercise the handshake error path. */
class BrokenChannel implements PairingChannel {
  closed = false;
  send(): void {}
  receive(): Promise<Uint8Array> {
    return Promise.reject(new Error('socket died'));
  }
  close(): void {
    this.closed = true;
  }
}

function qrFor(publicKey: Uint8Array, extras = ''): string {
  return `maverick://pair/v1?k=${bytesToBase64url(publicKey)}&t=token123&n=Studio${extras}`;
}

function makeController(): {
  controller: PairingController;
  history: ConnectionHistory;
} {
  const pinner = new TofuPinner(new InMemoryPinStorage());
  const history = new ConnectionHistory(new MemoryStore());
  return { controller: new PairingController(pinner, history), history };
}

describe('PairingController', () => {
  it('starts idle', () => {
    const { controller } = makeController();
    expect(controller.stage).toBe('idle');
    expect(controller.error).toBeNull();
    expect(controller.safetyNumber).toBeNull();
    expect(controller.pairResult).toBeNull();
  });

  it('runs a full handshake and reaches verify with a safety number', async () => {
    const { controller } = makeController();
    const desktop = generateKeyPair();
    const channel = new ResponderChannel(desktop);
    const stages: string[] = [];
    controller.subscribe(() => stages.push(controller.stage));

    await controller.pair(qrFor(desktop.publicKey), channel);

    expect(controller.stage).toBe('verify');
    expect(controller.safetyNumber).toMatch(/^\d{6}( \d{6}){4}$/);
    expect(controller.pairResult?.payload.token).toBe('token123');
    expect(channel.closed).toBe(true);
    expect(stages).toContain('parsing');
    expect(stages).toContain('handshaking');
    expect(stages).toContain('verify');
  });

  it('confirms and persists the device with name + token + pinned key', async () => {
    const { controller, history } = makeController();
    const desktop = generateKeyPair();
    await controller.pair(qrFor(desktop.publicKey), new ResponderChannel(desktop));
    controller.confirm('mac.ts.net', 8765);
    expect(controller.stage).toBe('paired');
    expect(history.hosts).toHaveLength(1);
    const h = history.hosts[0]!;
    expect(h.name).toBe('Studio');
    expect(h.token).toBe('token123');
    expect(h.pinnedKey).toBe(bytesToBase64url(desktop.publicKey));
  });

  it('confirm fails when there is no pairing result', () => {
    const { controller } = makeController();
    controller.confirm('mac', 1);
    expect(controller.stage).toBe('error');
    expect(controller.error).toMatch(/No pairing result/);
  });

  it('errors on a malformed QR string', async () => {
    const { controller } = makeController();
    await controller.pair('https://not-maverick', new ResponderChannel(generateKeyPair()));
    expect(controller.stage).toBe('error');
    expect(controller.error).toBeTruthy();
  });

  it('errors when the QR key does not match the handshake key', async () => {
    const { controller } = makeController();
    const desktop = generateKeyPair();
    const imposter = generateKeyPair();
    // QR advertises the imposter key but the channel speaks for `desktop`.
    await controller.pair(qrFor(imposter.publicKey), new ResponderChannel(desktop));
    expect(controller.stage).toBe('error');
  });

  it('errors and closes when the channel fails mid-handshake', async () => {
    const { controller } = makeController();
    const channel = new BrokenChannel();
    await controller.pair(qrFor(generateKeyPair().publicKey), channel);
    expect(controller.stage).toBe('error');
    expect(channel.closed).toBe(true);
  });

  it('confirms without a name when the QR omits it', async () => {
    const { controller, history } = makeController();
    const desktop = generateKeyPair();
    // Valid token, no `n` (name) param.
    const qr = `maverick://pair/v1?k=${bytesToBase64url(desktop.publicKey)}&t=tok`;
    await controller.pair(qr, new ResponderChannel(desktop));
    controller.confirm('h', 1);
    const h = history.hosts[0]!;
    expect(h.name).toBe('');
    expect(h.token).toBe('tok');
  });

  it('resets back to idle', async () => {
    const { controller } = makeController();
    const desktop = generateKeyPair();
    await controller.pair(qrFor(desktop.publicKey), new ResponderChannel(desktop));
    controller.reset();
    expect(controller.stage).toBe('idle');
    expect(controller.safetyNumber).toBeNull();
    expect(controller.pairResult).toBeNull();
  });
});

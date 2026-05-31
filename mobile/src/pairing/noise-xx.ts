/**
 * Noise_XX_25519_ChaChaPoly_SHA256 handshake.
 *
 * Pattern XX (mutual authentication, both static keys transmitted):
 *   -> e
 *   <- e, ee, s, es
 *   -> s, se
 *
 * The mobile client is the *initiator*; the desktop is the *responder*. After
 * the three messages both sides derive two transport keys (send/recv) plus a
 * shared handshake hash. Those keys are transport-independent — they protect
 * the session regardless of which TransportTier (LAN / iroh / relay) carries
 * the bytes — satisfying the "derive transport-independent session keys" goal.
 *
 * This is a from-scratch implementation of the Noise spec's symmetric/cipher
 * state on top of the @noble primitives. It is intentionally minimal: only the
 * XX pattern and only what pairing needs.
 */

import {
  aeadDecrypt,
  aeadEncrypt,
  concatBytes,
  DH_LEN,
  dh,
  generateKeyPair,
  hash,
  HASH_LEN,
  hkdfNoise,
  KeyPair,
  TAG_LEN,
  utf8Bytes,
} from './noise-crypto';

const PROTOCOL_NAME = 'Noise_XX_25519_ChaChaPoly_SHA256';

const EMPTY = new Uint8Array(0);

class CipherState {
  private key: Uint8Array | null = null;
  private counter = 0n;

  initializeKey(key: Uint8Array | null): void {
    this.key = key;
    this.counter = 0n;
  }

  /* istanbul ignore next -- spec helper unused by the minimal XX flow, which
     checks `this.key` directly in encrypt/decryptWithAd. */
  hasKey(): boolean {
    return this.key !== null;
  }

  encryptWithAd(ad: Uint8Array, plaintext: Uint8Array): Uint8Array {
    if (!this.key) return plaintext;
    const out = aeadEncrypt(this.key, this.counter, ad, plaintext);
    this.counter += 1n;
    return out;
  }

  decryptWithAd(ad: Uint8Array, ciphertext: Uint8Array): Uint8Array {
    if (!this.key) return ciphertext;
    const out = aeadDecrypt(this.key, this.counter, ad, ciphertext);
    this.counter += 1n;
    return out;
  }
}

/** A pair of cipher states for transport messages after the handshake. */
export interface TransportKeys {
  /** Key the initiator uses to send / responder uses to receive. */
  sendKey: Uint8Array;
  /** Key the initiator uses to receive / responder uses to send. */
  recvKey: Uint8Array;
  /** Final handshake hash — a channel binding usable for OOB verification. */
  handshakeHash: Uint8Array;
}

class SymmetricState {
  ck: Uint8Array;
  h: Uint8Array;
  readonly cipher = new CipherState();

  constructor() {
    const name = utf8Bytes(PROTOCOL_NAME);
    if (name.length <= HASH_LEN) {
      const padded = new Uint8Array(HASH_LEN);
      padded.set(name);
      this.h = padded;
    } else {
      /* istanbul ignore next -- PROTOCOL_NAME is exactly HASH_LEN (32) bytes,
         so this Noise-spec else-branch is unreachable for this protocol. */
      this.h = hash(name);
    }
    this.ck = this.h.slice();
  }

  mixKey(ikm: Uint8Array): void {
    const [ck, tempK] = hkdfNoise(this.ck, ikm, 2);
    this.ck = ck!;
    this.cipher.initializeKey(tempK!.slice(0, 32));
  }

  mixHash(data: Uint8Array): void {
    this.h = hash(concatBytes(this.h, data));
  }

  encryptAndHash(plaintext: Uint8Array): Uint8Array {
    const ciphertext = this.cipher.encryptWithAd(this.h, plaintext);
    this.mixHash(ciphertext);
    return ciphertext;
  }

  decryptAndHash(ciphertext: Uint8Array): Uint8Array {
    const plaintext = this.cipher.decryptWithAd(this.h, ciphertext);
    this.mixHash(ciphertext);
    return plaintext;
  }

  split(): { k1: Uint8Array; k2: Uint8Array } {
    const [k1, k2] = hkdfNoise(this.ck, EMPTY, 2);
    return { k1: k1!.slice(0, 32), k2: k2!.slice(0, 32) };
  }
}

type Step = 0 | 1 | 2 | 3;

export interface HandshakeOptions {
  /** Provide a fixed static keypair (tests / persisted identity). */
  staticKeyPair?: KeyPair;
  /** Provide a fixed ephemeral keypair (deterministic test vectors). */
  ephemeralKeyPair?: KeyPair;
  /** Responder must know the initiator's expected remote static key? No — XX
   *  transmits it; the responder learns `rs` during the handshake. */
}

/**
 * One party of an XX handshake. Initiator writes message 1 & 3 and reads
 * message 2; responder reads message 1 & 3 and writes message 2.
 */
export class NoiseXX {
  private readonly sym = new SymmetricState();
  private readonly s: KeyPair;
  private e: KeyPair | null = null;
  private re: Uint8Array | null = null;
  private rs: Uint8Array | null = null;
  private step: Step = 0;
  private readonly fixedEphemeral?: KeyPair;

  private constructor(
    public readonly role: 'initiator' | 'responder',
    opts: HandshakeOptions,
  ) {
    this.s = opts.staticKeyPair ?? generateKeyPair();
    if (opts.ephemeralKeyPair) this.fixedEphemeral = opts.ephemeralKeyPair;
    // XX has no pre-message keys; initialise just hashes the (empty) prologue.
    this.sym.mixHash(EMPTY);
  }

  static initiator(opts: HandshakeOptions = {}): NoiseXX {
    return new NoiseXX('initiator', opts);
  }

  static responder(opts: HandshakeOptions = {}): NoiseXX {
    return new NoiseXX('responder', opts);
  }

  /** This party's static public key. */
  get staticPublicKey(): Uint8Array {
    return this.s.publicKey;
  }

  /** The remote static public key, available once message 2 (init) / 3 (resp)
   *  has been processed. */
  get remoteStaticPublicKey(): Uint8Array | null {
    return this.rs ? this.rs.slice() : null;
  }

  get complete(): boolean {
    return this.step === 3;
  }

  private newEphemeral(): KeyPair {
    if (this.fixedEphemeral) return this.fixedEphemeral;
    return generateKeyPair();
  }

  /** Produce the next handshake message to send. */
  writeMessage(payload: Uint8Array = EMPTY): Uint8Array {
    if (this.role === 'initiator' && this.step === 0) return this.writeMsg1(payload);
    if (this.role === 'responder' && this.step === 1) return this.writeMsg2(payload);
    if (this.role === 'initiator' && this.step === 2) return this.writeMsg3(payload);
    throw new Error(`writeMessage called in invalid state (step ${this.step})`);
  }

  /** Consume the next handshake message received. Returns the decrypted payload. */
  readMessage(message: Uint8Array): Uint8Array {
    if (this.role === 'responder' && this.step === 0) return this.readMsg1(message);
    if (this.role === 'initiator' && this.step === 1) return this.readMsg2(message);
    if (this.role === 'responder' && this.step === 2) return this.readMsg3(message);
    throw new Error(`readMessage called in invalid state (step ${this.step})`);
  }

  /** Derive transport keys after `complete === true`. */
  finalize(): TransportKeys {
    if (!this.complete) throw new Error('Handshake not complete');
    const { k1, k2 } = this.sym.split();
    // k1 = initiator→responder, k2 = responder→initiator (Noise convention).
    if (this.role === 'initiator') {
      return { sendKey: k1, recvKey: k2, handshakeHash: this.sym.h.slice() };
    }
    return { sendKey: k2, recvKey: k1, handshakeHash: this.sym.h.slice() };
  }

  // --- message 1: -> e -----------------------------------------------------

  private writeMsg1(payload: Uint8Array): Uint8Array {
    this.e = this.newEphemeral();
    this.sym.mixHash(this.e.publicKey);
    const enc = this.sym.encryptAndHash(payload);
    this.step = 1;
    return concatBytes(this.e.publicKey, enc);
  }

  private readMsg1(message: Uint8Array): Uint8Array {
    this.re = message.slice(0, DH_LEN);
    this.sym.mixHash(this.re);
    const payload = this.sym.decryptAndHash(message.slice(DH_LEN));
    this.step = 1;
    return payload;
  }

  // --- message 2: <- e, ee, s, es ------------------------------------------

  private writeMsg2(payload: Uint8Array): Uint8Array {
    this.e = this.newEphemeral();
    this.sym.mixHash(this.e.publicKey);
    this.sym.mixKey(dh(this.e.privateKey, this.re!));
    const encStatic = this.sym.encryptAndHash(this.s.publicKey);
    this.sym.mixKey(dh(this.s.privateKey, this.re!));
    const encPayload = this.sym.encryptAndHash(payload);
    this.step = 2;
    return concatBytes(this.e.publicKey, encStatic, encPayload);
  }

  private readMsg2(message: Uint8Array): Uint8Array {
    let offset = 0;
    this.re = message.slice(offset, offset + DH_LEN);
    offset += DH_LEN;
    this.sym.mixHash(this.re);
    this.sym.mixKey(dh(this.e!.privateKey, this.re));

    const encStatic = message.slice(offset, offset + DH_LEN + TAG_LEN);
    offset += DH_LEN + TAG_LEN;
    this.rs = this.sym.decryptAndHash(encStatic);
    this.sym.mixKey(dh(this.e!.privateKey, this.rs));

    const payload = this.sym.decryptAndHash(message.slice(offset));
    this.step = 2;
    return payload;
  }

  // --- message 3: -> s, se -------------------------------------------------

  private writeMsg3(payload: Uint8Array): Uint8Array {
    const encStatic = this.sym.encryptAndHash(this.s.publicKey);
    this.sym.mixKey(dh(this.s.privateKey, this.re!));
    const encPayload = this.sym.encryptAndHash(payload);
    this.step = 3;
    return concatBytes(encStatic, encPayload);
  }

  private readMsg3(message: Uint8Array): Uint8Array {
    const encStatic = message.slice(0, DH_LEN + TAG_LEN);
    this.rs = this.sym.decryptAndHash(encStatic);
    this.sym.mixKey(dh(this.e!.privateKey, this.rs));
    const payload = this.sym.decryptAndHash(message.slice(DH_LEN + TAG_LEN));
    this.step = 3;
    return payload;
  }
}

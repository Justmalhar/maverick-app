import {
  base64urlToBytes,
  bytesToBase64url,
  DEFAULT_PAIRING_PORT,
  generateKeyPair,
  InitiatorPairingSession,
  InMemoryPinStorage,
  keyPairFromPrivate,
  NoiseXX,
  parsePairingPayload,
  PairingPayload,
  rendezvousTarget,
  TofuMismatchError,
  TofuPinner,
} from './index';
import {
  aeadDecrypt,
  aeadEncrypt,
  bytesEqual,
  dh,
  hkdfNoise,
} from './noise-crypto';

const KEY32 = new Uint8Array(32).map((_, i) => i + 1);
const KEY32_B64URL = bytesToBase64url(KEY32);

describe('base64url', () => {
  test('round-trips and strips padding + uses URL-safe alphabet', () => {
    const bytes = new Uint8Array([251, 255, 191, 0, 1]);
    const enc = bytesToBase64url(bytes);
    expect(enc).not.toContain('=');
    expect(enc).not.toContain('+');
    expect(enc).not.toContain('/');
    expect(Array.from(base64urlToBytes(enc))).toEqual(Array.from(bytes));
  });

  test('decodes both padded and unpadded inputs', () => {
    expect(Array.from(base64urlToBytes('aGk'))).toEqual([104, 105]);
    expect(Array.from(base64urlToBytes('aGk='))).toEqual([104, 105]);
  });

  test('rejects impossible length', () => {
    expect(() => base64urlToBytes('A')).toThrow();
  });
});

describe('parsePairingPayload', () => {
  test('parses a full payload with all params', () => {
    const eKey = bytesToBase64url(new Uint8Array(32).fill(7));
    const uri = `maverick://pair/v1?k=${KEY32_B64URL}&e=${eKey}&t=tok123&r=${encodeURIComponent(
      'wss://relay.example/abc',
    )}&n=${encodeURIComponent('Malhar MBA')}&f=AB12`;
    const p = parsePairingPayload(uri);
    expect(Array.from(p.staticPublicKey)).toEqual(Array.from(KEY32));
    expect(p.ephemeralPublicKey).toBeDefined();
    expect(p.token).toBe('tok123');
    expect(p.relay).toBe('wss://relay.example/abc');
    expect(p.name).toBe('Malhar MBA');
    expect(p.fingerprint).toBe('AB12');
  });

  test('parses a minimal payload (k + t only)', () => {
    const p = parsePairingPayload(`maverick://pair/v1?k=${KEY32_B64URL}&t=x`);
    expect(p.token).toBe('x');
    expect(p.ephemeralPublicKey).toBeUndefined();
    expect(p.relay).toBeUndefined();
    expect(p.name).toBeUndefined();
    expect(p.fingerprint).toBeUndefined();
  });

  test('rejects wrong scheme', () => {
    expect(() => parsePairingPayload('https://pair/v1?k=a&t=b')).toThrow();
  });

  test('rejects wrong path/version', () => {
    expect(() => parsePairingPayload(`maverick://pair/v2?k=${KEY32_B64URL}&t=x`)).toThrow();
    expect(() => parsePairingPayload(`maverick://connect?k=${KEY32_B64URL}&t=x`)).toThrow();
  });

  test('rejects missing required k', () => {
    expect(() => parsePairingPayload('maverick://pair/v1?t=x')).toThrow(/"k"/);
  });

  test('a maverick URI with no query string fails on the missing key', () => {
    // No "?" — base equals the prefix, query is empty, so parsing proceeds to
    // the required-param check and rejects the absent "k".
    expect(() => parsePairingPayload('maverick://pair/v1')).toThrow(/"k"/);
  });

  test('tolerates empty segments and valueless params in the query', () => {
    // Leading "&", a bare flag param ("x" with no "="), then the real params.
    const p = parsePairingPayload(`maverick://pair/v1?&x&k=${KEY32_B64URL}&t=tok`);
    expect(p.token).toBe('tok');
    expect(Array.from(p.staticPublicKey)).toEqual(Array.from(KEY32));
  });

  test('rejects missing required t', () => {
    expect(() => parsePairingPayload(`maverick://pair/v1?k=${KEY32_B64URL}`)).toThrow(/"t"/);
  });

  test('rejects a key of wrong length', () => {
    const short = bytesToBase64url(new Uint8Array(16).fill(1));
    expect(() => parsePairingPayload(`maverick://pair/v1?k=${short}&t=x`)).toThrow(/32 bytes/);
  });

  test('rejects non-base64url key', () => {
    expect(() => parsePairingPayload('maverick://pair/v1?k=****&t=x')).toThrow();
  });

  test('duplicate params take the first occurrence', () => {
    const p = parsePairingPayload(`maverick://pair/v1?k=${KEY32_B64URL}&t=first&t=second`);
    expect(p.token).toBe('first');
  });

  test('a malformed percent-escape in a param is passed through verbatim', () => {
    // "%" with no following hex digits would make decodeURIComponent throw;
    // safeDecodeURIComponent must catch and return the raw value instead.
    const p = parsePairingPayload(`maverick://pair/v1?k=${KEY32_B64URL}&t=tok&n=bad%zz`);
    expect(p.token).toBe('tok');
    expect(p.name).toBe('bad%zz');
  });
});

describe('rendezvousTarget', () => {
  function withRelay(relay?: string): PairingPayload {
    const base: PairingPayload = { staticPublicKey: KEY32, token: 't' };
    if (relay !== undefined) base.relay = relay;
    return base;
  }

  test('falls back to the LAN default when no relay hint is present', () => {
    expect(rendezvousTarget(withRelay())).toEqual({
      host: 'pair.local',
      port: DEFAULT_PAIRING_PORT,
    });
  });

  test('falls back when the relay hint is blank', () => {
    expect(rendezvousTarget(withRelay('   '))).toEqual({
      host: 'pair.local',
      port: DEFAULT_PAIRING_PORT,
    });
  });

  test('parses a scheme + host:port + path relay hint', () => {
    expect(rendezvousTarget(withRelay('wss://relay.example.com:9443/r/abc'))).toEqual(
      { host: 'relay.example.com', port: 9443 },
    );
  });

  test('parses a bare host:port relay hint', () => {
    expect(rendezvousTarget(withRelay('mac.ts.net:8765'))).toEqual({
      host: 'mac.ts.net',
      port: 8765,
    });
  });

  test('defaults the port for a bare host', () => {
    expect(rendezvousTarget(withRelay('mac.local'))).toEqual({
      host: 'mac.local',
      port: DEFAULT_PAIRING_PORT,
    });
  });

  test('keeps the default port and full authority for a bracketed IPv6 literal', () => {
    expect(rendezvousTarget(withRelay('ws://[fe80::1]'))).toEqual({
      host: '[fe80::1]',
      port: DEFAULT_PAIRING_PORT,
    });
  });

  test('parses a port after a bracketed IPv6 literal', () => {
    expect(rendezvousTarget(withRelay('ws://[fe80::1]:7000'))).toEqual({
      host: '[fe80::1]',
      port: 7000,
    });
  });

  test('treats a non-numeric port segment as part of the host', () => {
    expect(rendezvousTarget(withRelay('host:notaport'))).toEqual({
      host: 'host:notaport',
      port: DEFAULT_PAIRING_PORT,
    });
  });

  test('rejects an out-of-range port and keeps it on the host', () => {
    expect(rendezvousTarget(withRelay('host:70000'))).toEqual({
      host: 'host:70000',
      port: DEFAULT_PAIRING_PORT,
    });
  });

  test('falls back when the hint is only a scheme', () => {
    expect(rendezvousTarget(withRelay('wss://'))).toEqual({
      host: 'pair.local',
      port: DEFAULT_PAIRING_PORT,
    });
  });

  test('falls back when the authority is empty after stripping the path', () => {
    expect(rendezvousTarget(withRelay('wss:///just/a/path'))).toEqual({
      host: 'pair.local',
      port: DEFAULT_PAIRING_PORT,
    });
  });
});

describe('TofuPinner', () => {
  test('first use pins, subsequent matching use is firstUse=false', () => {
    const pinner = new TofuPinner(new InMemoryPinStorage());
    const key = new Uint8Array(32).fill(9);
    expect(pinner.verify('node', key).firstUse).toBe(true);
    expect(pinner.verify('node', key.slice()).firstUse).toBe(false);
    expect(pinner.pinned('node')).toBeDefined();
  });

  test('mismatched key throws TofuMismatchError', () => {
    const pinner = new TofuPinner(new InMemoryPinStorage());
    pinner.verify('node', new Uint8Array(32).fill(1));
    expect(() => pinner.verify('node', new Uint8Array(32).fill(2))).toThrow(TofuMismatchError);
  });

  test('different length key is treated as mismatch', () => {
    const pinner = new TofuPinner(new InMemoryPinStorage());
    pinner.verify('node', new Uint8Array(32).fill(1));
    expect(() => pinner.verify('node', new Uint8Array(31).fill(1))).toThrow(TofuMismatchError);
  });

  test('unpin allows re-pinning a new key', () => {
    const pinner = new TofuPinner(new InMemoryPinStorage());
    pinner.verify('node', new Uint8Array(32).fill(1));
    pinner.unpin('node');
    expect(pinner.pinned('node')).toBeUndefined();
    expect(pinner.verify('node', new Uint8Array(32).fill(2)).firstUse).toBe(true);
  });

  test('mismatch error carries node + base64url keys', () => {
    const pinner = new TofuPinner(new InMemoryPinStorage());
    pinner.verify('mac', new Uint8Array(32).fill(1));
    try {
      pinner.verify('mac', new Uint8Array(32).fill(2));
      throw new Error('should have thrown');
    } catch (e) {
      const err = e as TofuMismatchError;
      expect(err.nodeId).toBe('mac');
      expect(err.expected).not.toEqual(err.actual);
    }
  });
});

describe('noise-crypto primitives', () => {
  test('X25519 DH agreement is symmetric', () => {
    const a = generateKeyPair();
    const b = generateKeyPair();
    expect(Array.from(dh(a.privateKey, b.publicKey))).toEqual(
      Array.from(dh(b.privateKey, a.publicKey)),
    );
  });

  test('keyPairFromPrivate reconstructs the public key', () => {
    const a = generateKeyPair();
    const reconstructed = keyPairFromPrivate(a.privateKey);
    expect(Array.from(reconstructed.publicKey)).toEqual(Array.from(a.publicKey));
  });

  test('AEAD encrypt/decrypt round-trips with AAD and a counter', () => {
    const key = new Uint8Array(32).fill(3);
    const ad = new Uint8Array([1, 2, 3]);
    const pt = new Uint8Array([9, 8, 7, 6]);
    const ct = aeadEncrypt(key, 5n, ad, pt);
    expect(Array.from(aeadDecrypt(key, 5n, ad, ct))).toEqual(Array.from(pt));
  });

  test('AEAD decrypt fails with the wrong counter', () => {
    const key = new Uint8Array(32).fill(3);
    const ad = new Uint8Array(0);
    const ct = aeadEncrypt(key, 0n, ad, new Uint8Array([1]));
    expect(() => aeadDecrypt(key, 1n, ad, ct)).toThrow();
  });

  test('hkdfNoise returns the requested number of 32-byte outputs', () => {
    const ck = new Uint8Array(32).fill(1);
    const ikm = new Uint8Array(32).fill(2);
    const two = hkdfNoise(ck, ikm, 2);
    expect(two).toHaveLength(2);
    expect(two[0]!.length).toBe(32);
    const three = hkdfNoise(ck, ikm, 3);
    expect(three).toHaveLength(3);
  });

  test('bytesEqual', () => {
    expect(bytesEqual(new Uint8Array([1, 2]), new Uint8Array([1, 2]))).toBe(true);
    expect(bytesEqual(new Uint8Array([1, 2]), new Uint8Array([1, 3]))).toBe(false);
    expect(bytesEqual(new Uint8Array([1]), new Uint8Array([1, 2]))).toBe(false);
  });
});

describe('Noise_XX handshake', () => {
  test('two-party handshake completes and derives matching keys', () => {
    const initiator = NoiseXX.initiator();
    const responder = NoiseXX.responder();

    // -> e
    const m1 = initiator.writeMessage(new TextEncoder().encode('token'));
    const p1 = responder.readMessage(m1);
    expect(new TextDecoder().decode(p1)).toBe('token');

    // <- e, ee, s, es
    const m2 = responder.writeMessage();
    initiator.readMessage(m2);

    // -> s, se
    const m3 = initiator.writeMessage();
    responder.readMessage(m3);

    expect(initiator.complete).toBe(true);
    expect(responder.complete).toBe(true);

    const ik = initiator.finalize();
    const rk = responder.finalize();

    // Initiator's send key == responder's recv key, and vice versa.
    expect(Array.from(ik.sendKey)).toEqual(Array.from(rk.recvKey));
    expect(Array.from(ik.recvKey)).toEqual(Array.from(rk.sendKey));
    // Shared handshake hash (channel binding) matches.
    expect(Array.from(ik.handshakeHash)).toEqual(Array.from(rk.handshakeHash));
  });

  test('each party learns the other static key', () => {
    const iStatic = generateKeyPair();
    const rStatic = generateKeyPair();
    const initiator = NoiseXX.initiator({ staticKeyPair: iStatic });
    const responder = NoiseXX.responder({ staticKeyPair: rStatic });

    responder.readMessage(initiator.writeMessage());
    initiator.readMessage(responder.writeMessage());
    responder.readMessage(initiator.writeMessage());

    expect(Array.from(initiator.remoteStaticPublicKey!)).toEqual(Array.from(rStatic.publicKey));
    expect(Array.from(responder.remoteStaticPublicKey!)).toEqual(Array.from(iStatic.publicKey));
  });

  test('derived transport keys actually protect a transport message', () => {
    const initiator = NoiseXX.initiator();
    const responder = NoiseXX.responder();
    responder.readMessage(initiator.writeMessage());
    initiator.readMessage(responder.writeMessage());
    responder.readMessage(initiator.writeMessage());
    const ik = initiator.finalize();
    const rk = responder.finalize();

    const ad = new Uint8Array(0);
    const msg = new TextEncoder().encode('{"type":"list_sessions"}');
    const ct = aeadEncrypt(ik.sendKey, 0n, ad, msg);
    const pt = aeadDecrypt(rk.recvKey, 0n, ad, ct);
    expect(new TextDecoder().decode(pt)).toBe('{"type":"list_sessions"}');
  });

  test('a tampered handshake message breaks key agreement', () => {
    const initiator = NoiseXX.initiator();
    const responder = NoiseXX.responder();
    responder.readMessage(initiator.writeMessage());
    const m2 = responder.writeMessage();
    // Flip a byte in the encrypted static-key section.
    m2[40] = m2[40]! ^ 0xff;
    expect(() => initiator.readMessage(m2)).toThrow();
  });

  test('fixed ephemeral keys make the handshake deterministic', () => {
    const opts = {
      staticKeyPair: keyPairFromPrivate(new Uint8Array(32).fill(11)),
      ephemeralKeyPair: keyPairFromPrivate(new Uint8Array(32).fill(22)),
    };
    const run = () => {
      const i = NoiseXX.initiator(opts);
      const r = NoiseXX.responder({
        staticKeyPair: keyPairFromPrivate(new Uint8Array(32).fill(33)),
        ephemeralKeyPair: keyPairFromPrivate(new Uint8Array(32).fill(44)),
      });
      r.readMessage(i.writeMessage());
      i.readMessage(r.writeMessage());
      r.readMessage(i.writeMessage());
      return i.finalize().sendKey;
    };
    expect(Array.from(run())).toEqual(Array.from(run()));
  });

  test('out-of-order calls throw', () => {
    const initiator = NoiseXX.initiator();
    expect(() => initiator.readMessage(new Uint8Array(48))).toThrow();
    const responder = NoiseXX.responder();
    expect(() => responder.writeMessage()).toThrow();
    expect(() => initiator.finalize()).toThrow();
  });

  test('remoteStaticPublicKey is null before the remote static is learned', () => {
    expect(NoiseXX.initiator().remoteStaticPublicKey).toBeNull();
  });
});

describe('InitiatorPairingSession + responder', () => {
  function payloadFor(staticPub: Uint8Array, name = 'mac'): PairingPayload {
    return { staticPublicKey: staticPub, token: 'tok', name };
  }

  test('full pairing: handshake completes, key matches QR, TOFU pins', () => {
    const desktopStatic = generateKeyPair();
    const pinner = new TofuPinner(new InMemoryPinStorage());
    const responder = NoiseXX.responder({ staticKeyPair: desktopStatic });

    const session = new InitiatorPairingSession(
      payloadFor(desktopStatic.publicKey),
      pinner,
    );

    const m1 = session.start();
    expect(new TextDecoder().decode(responder.readMessage(m1))).toBe('tok');

    const m2 = responder.writeMessage();
    const m3 = session.handleMessage2(m2);
    responder.readMessage(m3);

    const result = session.complete();
    expect(result.firstUse).toBe(true);
    expect(Array.from(result.remoteStaticPublicKey)).toEqual(
      Array.from(desktopStatic.publicKey),
    );

    const rk = responder.finalize();
    expect(Array.from(result.keys.sendKey)).toEqual(Array.from(rk.recvKey));
    expect(pinner.pinned('mac')).toBeDefined();
  });

  test('complete() throws if called a second time', () => {
    const desktopStatic = generateKeyPair();
    const pinner = new TofuPinner(new InMemoryPinStorage());
    const responder = NoiseXX.responder({ staticKeyPair: desktopStatic });
    const session = new InitiatorPairingSession(
      payloadFor(desktopStatic.publicKey),
      pinner,
    );
    responder.readMessage(session.start());
    responder.readMessage(session.handleMessage2(responder.writeMessage()));
    session.complete();
    expect(() => session.complete()).toThrow(/already completed/);
  });

  test('aborts when the handshake static key does not match the QR code', () => {
    const desktopStatic = generateKeyPair();
    const impostor = generateKeyPair();
    const pinner = new TofuPinner(new InMemoryPinStorage());
    // Responder answers with a DIFFERENT static key than the QR advertised.
    const responder = NoiseXX.responder({ staticKeyPair: impostor });
    const session = new InitiatorPairingSession(
      payloadFor(desktopStatic.publicKey),
      pinner,
    );
    responder.readMessage(session.start());
    expect(() => session.handleMessage2(responder.writeMessage())).toThrow(
      /does not match the scanned QR/,
    );
  });

  test('cannot start twice / cannot complete before handshake', () => {
    const desktopStatic = generateKeyPair();
    const pinner = new TofuPinner(new InMemoryPinStorage());
    const session = new InitiatorPairingSession(payloadFor(desktopStatic.publicKey), pinner);
    session.start();
    expect(() => session.start()).toThrow(/already started/);
    expect(() => session.complete()).toThrow(/not complete/);
  });

  test('handleMessage2 before start throws', () => {
    const desktopStatic = generateKeyPair();
    const pinner = new TofuPinner(new InMemoryPinStorage());
    const session = new InitiatorPairingSession(payloadFor(desktopStatic.publicKey), pinner);
    expect(() => session.handleMessage2(new Uint8Array(80))).toThrow(/not started/);
  });

  test('exposes the client static public key', () => {
    const desktopStatic = generateKeyPair();
    const pinner = new TofuPinner(new InMemoryPinStorage());
    const session = new InitiatorPairingSession(payloadFor(desktopStatic.publicKey), pinner);
    expect(session.staticPublicKey.length).toBe(32);
  });

  test('uses a supplied static keypair as the client identity', () => {
    const desktopStatic = generateKeyPair();
    const clientStatic = generateKeyPair();
    const pinner = new TofuPinner(new InMemoryPinStorage());
    const session = new InitiatorPairingSession(
      payloadFor(desktopStatic.publicKey),
      pinner,
      'node',
      clientStatic,
    );
    expect(Array.from(session.staticPublicKey)).toEqual(
      Array.from(clientStatic.publicKey),
    );
  });

  test('uses payload name as default nodeId, falls back to "default"', () => {
    const desktopStatic = generateKeyPair();
    const pinner = new TofuPinner(new InMemoryPinStorage());
    const responder = NoiseXX.responder({ staticKeyPair: desktopStatic });
    const session = new InitiatorPairingSession(
      { staticPublicKey: desktopStatic.publicKey, token: 't' },
      pinner,
    );
    responder.readMessage(session.start());
    responder.readMessage(session.handleMessage2(responder.writeMessage()));
    session.complete();
    expect(pinner.pinned('default')).toBeDefined();
  });
});

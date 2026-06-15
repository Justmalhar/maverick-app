//! Live Noise_XX **responder** harness for the MaverickNoise interop test.
//!
//! This is a self-contained stdio program that uses the SAME `snow` crate and
//! the SAME cipher-suite features the maverick daemon's `NoiseResponder` uses
//! (see `maverick/src-tauri/core/src/remote/pairing.rs` and the workspace
//! `Cargo.toml` snow feature list). It is deliberately NOT part of the daemon
//! workspace — it is a fixture under the MaverickNoise Swift package so the
//! Swift initiator can be proven byte-compatible against real `snow` with no
//! sockets, no WebSocket, and no daemon bind-policy involved.
//!
//! ## Wire protocol over stdio (one base64url line per frame)
//!
//! 1. On startup the harness prints ONE line to stdout:
//!        `<responder_static_pub_b64url> <token_b64url>`
//!    These play the role of the QR `k` and `t` fields for the Swift side.
//! 2. Read msg1 (base64url line) from stdin -> `read_message`.
//!    Verify the decrypted payload bytes == the chosen 16-byte token.
//! 3. Write msg2 (base64url line) to stdout (`<- e, ee, s, es`, empty payload).
//! 4. Read msg3 (base64url line) from stdin (`-> s, se`); `into_transport_mode`.
//! 5. Read ONE transport frame (base64url) from stdin, decrypt; assert it equals
//!    `{"type":"list_sessions"}`.
//! 6. Write ONE transport frame (base64url) to stdout = encrypt of
//!    `{"type":"session_list","sessions":[]}`.
//! 7. Exit 0.
//!
//! Any protocol/crypto failure -> stderr message + non-zero exit.

use std::io::{self, BufRead, Write};

use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use base64::Engine;
use snow::params::NoiseParams;

const NOISE_PARAMS: &str = "Noise_XX_25519_ChaChaPoly_SHA256";
const TOKEN_BYTES: usize = 16;

const LIST_SESSIONS: &[u8] = b"{\"type\":\"list_sessions\"}";
const SESSION_LIST: &[u8] = b"{\"type\":\"session_list\",\"sessions\":[]}";

fn b64(bytes: &[u8]) -> String {
    URL_SAFE_NO_PAD.encode(bytes)
}

fn unb64(s: &str) -> Result<Vec<u8>, String> {
    URL_SAFE_NO_PAD
        .decode(s.trim().trim_end_matches('=').as_bytes())
        .map_err(|e| format!("invalid base64url: {e}"))
}

fn read_line(stdin: &mut impl BufRead) -> Result<String, String> {
    let mut line = String::new();
    let n = stdin
        .read_line(&mut line)
        .map_err(|e| format!("stdin read: {e}"))?;
    if n == 0 {
        return Err("unexpected EOF on stdin".into());
    }
    Ok(line.trim().to_string())
}

fn run() -> Result<(), String> {
    let params: NoiseParams = NOISE_PARAMS
        .parse()
        .map_err(|e| format!("params parse: {e}"))?;

    // Responder static identity (the "QR k" the Swift side will assert against).
    let keypair = snow::Builder::new(params.clone())
        .generate_keypair()
        .map_err(|e| format!("keygen: {e}"))?;

    let mut responder = snow::Builder::new(params)
        .prologue(&[])
        .map_err(|e| format!("prologue: {e}"))?
        .local_private_key(&keypair.private)
        .map_err(|e| format!("local key: {e}"))?
        .build_responder()
        .map_err(|e| format!("build responder: {e}"))?;

    // The 16-byte single-use pairing token, rides as the msg1 payload.
    let mut token = [0u8; TOKEN_BYTES];
    getrandom_token(&mut token)?;

    let stdout = io::stdout();
    let mut out = stdout.lock();
    let stdin = io::stdin();
    let mut input = stdin.lock();

    // First line: responder static pub + token (the "QR" material).
    writeln!(out, "{} {}", b64(&keypair.public), b64(&token))
        .map_err(|e| format!("stdout write: {e}"))?;
    out.flush().map_err(|e| format!("flush: {e}"))?;

    // --- msg1: -> e, payload = token ---
    let msg1 = unb64(&read_line(&mut input)?)?;
    let mut payload = vec![0u8; msg1.len()];
    let n = responder
        .read_message(&msg1, &mut payload)
        .map_err(|e| format!("read msg1: {e}"))?;
    payload.truncate(n);
    if payload != token {
        return Err(format!(
            "token mismatch: got {} bytes {:?}, want {:?}",
            payload.len(),
            payload,
            token
        ));
    }

    // --- msg2: <- e, ee, s, es (empty payload) ---
    let mut buf = vec![0u8; 4096];
    let n = responder
        .write_message(&[], &mut buf)
        .map_err(|e| format!("write msg2: {e}"))?;
    buf.truncate(n);
    writeln!(out, "{}", b64(&buf)).map_err(|e| format!("stdout write: {e}"))?;
    out.flush().map_err(|e| format!("flush: {e}"))?;

    // --- msg3: -> s, se ---
    let msg3 = unb64(&read_line(&mut input)?)?;
    let mut p3 = vec![0u8; msg3.len()];
    responder
        .read_message(&msg3, &mut p3)
        .map_err(|e| format!("read msg3: {e}"))?;

    let mut transport = responder
        .into_transport_mode()
        .map_err(|e| format!("into_transport_mode: {e}"))?;

    // --- transport frame in: encrypted {"type":"list_sessions"} ---
    let frame_in = unb64(&read_line(&mut input)?)?;
    let mut dec = vec![0u8; frame_in.len()];
    let n = transport
        .read_message(&frame_in, &mut dec)
        .map_err(|e| format!("transport decrypt: {e}"))?;
    dec.truncate(n);
    if dec != LIST_SESSIONS {
        return Err(format!(
            "unexpected app frame: {:?}",
            String::from_utf8_lossy(&dec)
        ));
    }

    // --- transport frame out: encrypted session_list reply ---
    let mut reply = vec![0u8; SESSION_LIST.len() + 16];
    let n = transport
        .write_message(SESSION_LIST, &mut reply)
        .map_err(|e| format!("transport encrypt: {e}"))?;
    reply.truncate(n);
    writeln!(out, "{}", b64(&reply)).map_err(|e| format!("stdout write: {e}"))?;
    out.flush().map_err(|e| format!("flush: {e}"))?;

    Ok(())
}

/// Fill `buf` with OS randomness via `getrandom` — the same RNG crate the
/// daemon uses to mint pairing tokens (`getrandom::getrandom` in pairing.rs).
fn getrandom_token(buf: &mut [u8]) -> Result<(), String> {
    getrandom::getrandom(buf).map_err(|e| format!("getrandom: {e}"))
}

fn main() {
    if let Err(e) = run() {
        eprintln!("noise-harness error: {e}");
        std::process::exit(1);
    }
}

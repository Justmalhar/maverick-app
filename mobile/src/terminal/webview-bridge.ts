/**
 * xterm.js ⇄ react-native-webview bridge. The Swift terminal hosts SwiftTerm
 * natively; on RN we host xterm.js inside a WebView (per the RN-2 plan) and
 * speak a tiny JSON message protocol across the bridge:
 *
 *   RN → WebView (injected JS):   write(text) / fit() / clear()
 *   WebView → RN (postMessage):   { t: 'data', d }  user keystrokes
 *                                 { t: 'resize', cols, rows }
 *                                 { t: 'ready' }
 *
 * `terminalHtml()` returns a self-contained document that loads xterm from a CDN
 * and wires those handlers. Keeping it a pure string keeps it unit-testable and
 * out of the component. The bridge codecs below are what the tests exercise.
 *
 * Security: the WebView bridges to the user's PTY, so an attacker who can alter
 * the xterm bundle in flight (MITM) or at the CDN (supply chain) gets script
 * execution against the terminal. Every <script>/<link> therefore pins an
 * exact version AND carries a Subresource Integrity hash + crossorigin, so the
 * WebView refuses to execute any bytes that don't match the pinned digest.
 * (Bundling the assets locally is the stronger fix but is deferred to a build
 * step that can inline the minified packages — tracked in RN-2 follow-up.)
 */

export interface ReadyMessage {
  t: 'ready';
}
export interface DataMessage {
  t: 'data';
  d: string;
}
export interface ResizeMessage {
  t: 'resize';
  cols: number;
  rows: number;
}
export type WebViewMessage = ReadyMessage | DataMessage | ResizeMessage;

/** Parse a postMessage payload from the webview; null on anything malformed. */
export function parseWebViewMessage(raw: string): WebViewMessage | null {
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    return null;
  }
  if (typeof parsed !== 'object' || parsed === null) return null;
  const o = parsed as Record<string, unknown>;
  switch (o.t) {
    case 'ready':
      return { t: 'ready' };
    case 'data':
      return typeof o.d === 'string' ? { t: 'data', d: o.d } : null;
    case 'resize':
      return typeof o.cols === 'number' && typeof o.rows === 'number'
        ? { t: 'resize', cols: o.cols, rows: o.rows }
        : null;
    default:
      return null;
  }
}

/** JS to inject into the webview to write a chunk into the terminal. */
export function writeScript(text: string): string {
  return `window.__mvWrite && window.__mvWrite(${JSON.stringify(text)}); true;`;
}

/** JS to clear the terminal. */
export function clearScript(): string {
  return `window.__mvClear && window.__mvClear(); true;`;
}

const XTERM_VERSION = '5.5.0';
const ADDON_FIT_VERSION = '0.10.0';

// Subresource Integrity digests for the exact pinned bundles above. SHA-384 of
// the bytes served by jsDelivr; regenerate with:
//   openssl dgst -sha384 -binary <file> | openssl base64 -A
const XTERM_CSS_SRI =
  'sha384-tStR1zLfWgsiXCF3IgfB3lBa8KmBe/lG287CL9WCeKgQYcp1bjb4/+mwN6oti4Co';
const XTERM_JS_SRI =
  'sha384-J4qzUjBl1FxyLsl/kQPQIOeINsmp17OHYXDOMpMxlKX53ZfYsL+aWHpgArvOuof9';
const ADDON_FIT_JS_SRI =
  'sha384-XGqKrV8Jrukp1NITJbOEHwg01tNkuXr6uB6YEj69ebpYU3v7FvoGgEg23C1Gcehk';

/** Self-contained xterm host document. `seed` is written once on ready. */
export function terminalHtml(seed = ''): string {
  return `<!DOCTYPE html>
<html>
<head>
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no" />
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/@xterm/xterm@${XTERM_VERSION}/css/xterm.min.css" integrity="${XTERM_CSS_SRI}" crossorigin="anonymous" />
<style>html,body,#t{margin:0;height:100%;background:#000}</style>
</head>
<body>
<div id="t"></div>
<script src="https://cdn.jsdelivr.net/npm/@xterm/xterm@${XTERM_VERSION}/lib/xterm.min.js" integrity="${XTERM_JS_SRI}" crossorigin="anonymous"></script>
<script src="https://cdn.jsdelivr.net/npm/@xterm/addon-fit@${ADDON_FIT_VERSION}/lib/addon-fit.min.js" integrity="${ADDON_FIT_JS_SRI}" crossorigin="anonymous"></script>
<script>
(function(){
  var post = function(m){ window.ReactNativeWebView && window.ReactNativeWebView.postMessage(JSON.stringify(m)); };
  var term = new window.Terminal({ convertEol:false, scrollback:4000, fontSize:13, theme:{background:'#000'} });
  var fit = new window.FitAddon.FitAddon();
  term.loadAddon(fit);
  term.open(document.getElementById('t'));
  try { fit.fit(); } catch(e){}
  window.__mvWrite = function(d){ term.write(d); };
  window.__mvClear = function(){ term.clear(); };
  term.onData(function(d){ post({ t:'data', d:d }); });
  var sendResize = function(){ try { fit.fit(); } catch(e){} post({ t:'resize', cols:term.cols, rows:term.rows }); };
  window.addEventListener('resize', sendResize);
  var seed = ${JSON.stringify(seed)};
  if (seed) term.write(seed);
  post({ t:'ready' });
  sendResize();
})();
</script>
</body>
</html>`;
}

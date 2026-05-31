import {
  clearScript,
  parseWebViewMessage,
  terminalHtml,
  writeScript,
} from './webview-bridge';

describe('parseWebViewMessage', () => {
  it('parses ready, data, and resize messages', () => {
    expect(parseWebViewMessage('{"t":"ready"}')).toEqual({ t: 'ready' });
    expect(parseWebViewMessage('{"t":"data","d":"ls\\r"}')).toEqual({
      t: 'data',
      d: 'ls\r',
    });
    expect(parseWebViewMessage('{"t":"resize","cols":80,"rows":24}')).toEqual({
      t: 'resize',
      cols: 80,
      rows: 24,
    });
  });

  it('rejects malformed JSON and non-objects', () => {
    expect(parseWebViewMessage('not json')).toBeNull();
    expect(parseWebViewMessage('42')).toBeNull();
    expect(parseWebViewMessage('null')).toBeNull();
  });

  it('rejects messages with wrong/missing fields', () => {
    expect(parseWebViewMessage('{"t":"data"}')).toBeNull();
    expect(parseWebViewMessage('{"t":"data","d":5}')).toBeNull();
    expect(parseWebViewMessage('{"t":"resize","cols":"x","rows":24}')).toBeNull();
    expect(parseWebViewMessage('{"t":"resize","cols":80}')).toBeNull();
    expect(parseWebViewMessage('{"t":"unknown"}')).toBeNull();
  });
});

describe('webview scripts', () => {
  it('escapes the write payload as a JSON string', () => {
    const s = writeScript('a"b\nc');
    expect(s).toContain('__mvWrite');
    expect(s).toContain(JSON.stringify('a"b\nc'));
  });

  it('builds a clear script', () => {
    expect(clearScript()).toContain('__mvClear');
  });
});

describe('terminalHtml', () => {
  it('embeds xterm, the bridge, and an empty seed by default', () => {
    const html = terminalHtml();
    expect(html).toContain('xterm.min.js');
    expect(html).toContain('__mvWrite');
    expect(html).toContain('ReactNativeWebView');
    expect(html).toContain('var seed = "";');
  });

  it('embeds an escaped seed', () => {
    const html = terminalHtml('hi\n"there"');
    expect(html).toContain(JSON.stringify('hi\n"there"'));
  });

  it('pins the xterm version and guards every CDN tag with SRI + crossorigin', () => {
    const html = terminalHtml();
    // Pinned, real versions (the previous @5.3.0 scoped package did not exist).
    expect(html).toContain('@xterm/xterm@5.5.0');
    expect(html).toContain('@xterm/addon-fit@0.10.0');
    // No remote <script>/<link> may load without an integrity hash.
    const cdnTags = html.match(/(?:src|href)="https:\/\/[^"]+"/g) ?? [];
    expect(cdnTags).toHaveLength(3);
    const integrities = html.match(/integrity="sha384-[^"]+"/g) ?? [];
    expect(integrities).toHaveLength(3);
    expect((html.match(/crossorigin="anonymous"/g) ?? [])).toHaveLength(3);
  });
});

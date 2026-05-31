import {
  baseName,
  batchSummary,
  toolDisplayName,
  toolFailed,
} from './tool-display';
import { customTool, tool } from '@/protocol';
import { toolCall } from '@/test/fixtures';

describe('toolDisplayName', () => {
  it('maps every known tool kind', () => {
    expect(toolDisplayName(tool('read'))).toBe('Read');
    expect(toolDisplayName(tool('webFetch'))).toBe('Fetch');
    expect(toolDisplayName(tool('listMcpResources'))).toBe('MCP');
    expect(toolDisplayName(tool('shareOnboardingGuide'))).toBe('Share');
  });

  it('passes a custom tool name through', () => {
    expect(toolDisplayName(customTool('my_tool'))).toBe('my_tool');
  });
});

describe('toolFailed', () => {
  it('detects an error', () => {
    expect(toolFailed(toolCall())).toBe(false);
    expect(toolFailed(toolCall({ error: 'boom' }))).toBe(true);
  });
});

describe('baseName', () => {
  it('returns the last path segment, ignoring trailing slashes', () => {
    expect(baseName('/a/b/c.ts')).toBe('c.ts');
    expect(baseName('/a/b/')).toBe('b');
    expect(baseName('file.ts')).toBe('file.ts');
  });
});

describe('batchSummary', () => {
  it('summarises an empty batch', () => {
    expect(batchSummary([])).toBe('No tools');
  });

  it('lists up to two tool names', () => {
    expect(
      batchSummary([toolCall({ tool: tool('read') })]),
    ).toBe('Read');
    expect(
      batchSummary([
        toolCall({ tool: tool('read') }),
        toolCall({ tool: tool('bash') }),
      ]),
    ).toBe('Read, Bash');
  });

  it('shows an overflow count and failures', () => {
    const summary = batchSummary([
      toolCall({ tool: tool('read') }),
      toolCall({ tool: tool('bash') }),
      toolCall({ tool: tool('edit') }),
      toolCall({ tool: tool('grep'), error: 'x' }),
    ]);
    expect(summary).toBe('Read, Bash +2 · 1 failed');
  });
});

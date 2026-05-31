import { act, fireEvent } from '@testing-library/react-native';
import { GitDiffView } from './GitDiffView';
import { makeAppModel, renderWithApp } from '@/test/render';
import { ServerMessage } from '@/protocol';

function deliver(app: ReturnType<typeof makeAppModel>, msg: ServerMessage): void {
  act(() => {
    app.git.handle(msg);
  });
}

describe('GitDiffView', () => {
  it('renders changed files and opens a diff on tap', () => {
    const app = makeAppModel();
    const { getByText, queryByTestId } = renderWithApp(
      <GitDiffView repoPath="/proj" />,
      app,
    );
    deliver(app, {
      type: 'git_status_result',
      requestId: pendingStatusId(app),
      status: {
        isRepo: true,
        branch: 'main',
        ahead: 1,
        behind: 0,
        files: [{ path: 'src/a.ts', status: 'M', staged: false }],
      },
    });
    expect(getByText('src/a.ts')).toBeTruthy();
    fireEvent.press(getByText('src/a.ts'));
    deliver(app, {
      type: 'git_diff_result',
      requestId: pendingDiffId(app),
      file: 'src/a.ts',
      diff: '@@ -1 +1 @@\n-old\n+new',
      truncated: false,
    });
    expect(queryByTestId('diff-body')).toBeTruthy();
  });

  it('shows an error message', () => {
    const app = makeAppModel();
    const { getByText } = renderWithApp(<GitDiffView repoPath="/proj" />, app);
    deliver(app, {
      type: 'git_status_failed',
      requestId: pendingStatusId(app),
      message: 'not a repo here',
    });
    expect(getByText('not a repo here')).toBeTruthy();
  });
});

// The model mints request ids internally; read the in-flight ids (test-only).
function pendingStatusId(app: ReturnType<typeof makeAppModel>): string {
  return (app.git as unknown as { pendingStatusRequestId: string | null })
    .pendingStatusRequestId!;
}
function pendingDiffId(app: ReturnType<typeof makeAppModel>): string {
  const reqs = (app.git as unknown as { pendingDiffRequests: Map<string, string> })
    .pendingDiffRequests;
  return [...reqs.keys()][0]!;
}

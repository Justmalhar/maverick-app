import { act, fireEvent } from '@testing-library/react-native';
import { FileExplorerView } from './FileExplorerView';
import { makeAppModel, renderWithApp } from '@/test/render';
import { ServerMessage } from '@/protocol';

function pendingIndexId(app: ReturnType<typeof makeAppModel>): string {
  return (app.index as unknown as { pendingRequestId: string | null })
    .pendingRequestId!;
}

function deliver(app: ReturnType<typeof makeAppModel>, msg: ServerMessage): void {
  act(() => {
    app.index.handle(msg);
  });
}

describe('FileExplorerView', () => {
  it('renders the indexed tree and drills into a directory', () => {
    const app = makeAppModel();
    const { getByText, queryByText } = renderWithApp(
      <FileExplorerView rootPath="/proj" />,
      app,
    );
    deliver(app, {
      type: 'index_chunk',
      requestId: pendingIndexId(app),
      root: '/proj',
      entries: [
        { path: 'src', isDirectory: true },
        { path: 'src/a.ts', isDirectory: false },
        { path: 'README.md', isDirectory: false },
      ],
      complete: true,
    });
    expect(getByText('src')).toBeTruthy();
    expect(getByText('README.md')).toBeTruthy();
    fireEvent.press(getByText('src'));
    expect(getByText('a.ts')).toBeTruthy();
    // Navigate back up.
    fireEvent.press(getByText(/\.\. \/src/));
    expect(queryByText('README.md')).toBeTruthy();
  });

  it('renders an index error', () => {
    const app = makeAppModel();
    const { getByText } = renderWithApp(<FileExplorerView rootPath="/proj" />, app);
    deliver(app, {
      type: 'index_failed',
      requestId: pendingIndexId(app),
      message: 'permission denied',
    });
    expect(getByText('permission denied')).toBeTruthy();
  });
});

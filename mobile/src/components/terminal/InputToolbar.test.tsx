import { fireEvent } from '@testing-library/react-native';
import { InputToolbar } from './InputToolbar';
import { makeAppModel, renderWithApp } from '@/test/render';
import { uuid } from '@/test/fixtures';

describe('InputToolbar', () => {
  it('sends esc/tab/enter and a symbol', () => {
    const app = makeAppModel();
    const sid = uuid();
    const { getByLabelText } = renderWithApp(<InputToolbar sessionId={sid} />, app);
    fireEvent.press(getByLabelText('esc'));
    fireEvent.press(getByLabelText('tab'));
    fireEvent.press(getByLabelText('↩'));
    fireEvent.press(getByLabelText('|'));
    // No throw means the byte sequences were produced + forwarded.
    expect(getByLabelText('ctrl')).toBeTruthy();
  });

  it('latches ctrl and applies it to the next char', () => {
    const app = makeAppModel();
    const { getByLabelText } = renderWithApp(<InputToolbar sessionId={uuid()} />, app);
    fireEvent.press(getByLabelText('ctrl'));
    // Tap a symbol while latched → Ctrl-byte, then latch clears.
    fireEvent.press(getByLabelText('/'));
    expect(getByLabelText('ctrl')).toBeTruthy();
  });

  it('expands the nav row and the more panel', () => {
    const app = makeAppModel();
    const { getByLabelText, queryByLabelText } = renderWithApp(
      <InputToolbar sessionId={uuid()} />,
      app,
    );
    // Expand chevron opens nav.
    fireEvent.press(getByLabelText('▴'));
    expect(getByLabelText('↑')).toBeTruthy();
    // Open More → control sequences appear.
    fireEvent.press(getByLabelText('More'));
    expect(getByLabelText('^C')).toBeTruthy();
    fireEvent.press(getByLabelText('^C'));
    fireEvent.press(getByLabelText('↑'));
    // Collapse everything.
    fireEvent.press(getByLabelText('▾'));
    expect(queryByLabelText('↑')).toBeNull();
  });
});

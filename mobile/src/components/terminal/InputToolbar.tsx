/**
 * Keyboard accessory toolbar, ported from the Swift InputToolbar + CursorPad.
 * Quick keys (esc/tab/ctrl/↩/symbols), an expandable arrow/nav row, and a More
 * panel of control sequences. All byte mapping lives in InputKeyState; this
 * component only renders caps and forwards the produced bytes to the session.
 */
import { useRef, useState } from 'react';
import { ScrollView, StyleSheet, View } from 'react-native';
import { useApp } from '../AppProvider';
import { InputKeyState } from '@/terminal/input-keys';
import { KeyCap } from '../ui/KeyCap';
import { space, theme } from '../theme';

const NAV_KEYS = ['up', 'down', 'left', 'right', 'home', 'end', 'pgUp', 'pgDn'];
const NAV_LABELS: Record<string, string> = {
  up: '↑',
  down: '↓',
  left: '←',
  right: '→',
  home: 'home',
  end: 'end',
  pgUp: 'pgUp',
  pgDn: 'pgDn',
};
const CONTROLS = ['^C', '^D', '^Z', '^L', '^A', '^E', '^R', '^W', '^U', '^K'];
const SYMBOLS = ['|', '~', '/', '-', '(', ')', '[', ']', '{', '}', '<', '>'];

export function InputToolbar({ sessionId }: { sessionId: string }): React.JSX.Element {
  const app = useApp();
  const keys = useRef(new InputKeyState()).current;
  const [navOpen, setNavOpen] = useState(false);
  const [moreOpen, setMoreOpen] = useState(false);
  const [, force] = useState(0);

  const out = (seq: string | undefined): void => {
    if (seq !== undefined) app.client.input(sessionId, seq);
    force((n) => n + 1);
  };

  return (
    <View style={styles.root}>
      {moreOpen && (
        <ScrollView horizontal showsHorizontalScrollIndicator={false} style={styles.row}>
          {CONTROLS.map((c) => (
            <KeyCap
              key={c}
              label={c}
              variant={c === '^C' ? 'danger' : 'neutral'}
              onPress={() => out(keys.control(c))}
            />
          ))}
        </ScrollView>
      )}
      {navOpen && (
        <ScrollView horizontal showsHorizontalScrollIndicator={false} style={styles.row}>
          {NAV_KEYS.map((k) => (
            <KeyCap key={k} label={NAV_LABELS[k]!} onPress={() => out(keys.nav(k))} />
          ))}
          <KeyCap
            label={moreOpen ? 'Less' : 'More'}
            onPress={() => setMoreOpen((v) => !v)}
          />
        </ScrollView>
      )}
      <View style={styles.primary}>
        <ScrollView horizontal showsHorizontalScrollIndicator={false} style={styles.row}>
          <KeyCap label="esc" onPress={() => out(keys.esc())} />
          <KeyCap label="tab" onPress={() => out(keys.tab())} />
          <KeyCap
            label="ctrl"
            variant={keys.isCtrlLatched ? 'latched' : 'neutral'}
            onPress={() => {
              keys.tapCtrl();
              force((n) => n + 1);
            }}
          />
          <KeyCap label="↩" onPress={() => out(keys.enter())} />
          {SYMBOLS.map((s) => (
            <KeyCap key={s} label={s} minWidth={30} onPress={() => out(keys.applyChar(s))} />
          ))}
        </ScrollView>
        <KeyCap
          label={navOpen ? '▾' : '▴'}
          onPress={() => {
            if (navOpen) {
              setNavOpen(false);
              setMoreOpen(false);
            } else {
              setNavOpen(true);
            }
          }}
        />
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  root: {
    backgroundColor: theme.bgElevated,
    borderTopWidth: StyleSheet.hairlineWidth,
    borderColor: theme.stroke,
  },
  row: { paddingHorizontal: space.sm, paddingVertical: space.xs },
  primary: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: space.sm,
    paddingRight: space.sm,
  },
});

/** A tappable terminal key cap, ported from the Swift KeyCap. */
import { Pressable, StyleSheet, Text } from 'react-native';
import { radius, theme } from '../theme';

export type KeyCapStyle = 'neutral' | 'latched' | 'danger';

export function KeyCap({
  label,
  onPress,
  variant = 'neutral',
  minWidth = 38,
}: {
  label: string;
  onPress: () => void;
  variant?: KeyCapStyle;
  minWidth?: number;
}): React.JSX.Element {
  const tint =
    variant === 'danger'
      ? theme.danger
      : variant === 'latched'
        ? theme.onAccent
        : theme.textPrimary;
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel={label}
      onPress={onPress}
      style={[
        styles.cap,
        { minWidth },
        variant === 'latched' && styles.latched,
      ]}
    >
      <Text style={[styles.label, { color: tint }]}>{label}</Text>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  cap: {
    height: 34,
    paddingHorizontal: 8,
    borderRadius: radius.sm,
    backgroundColor: 'rgba(255,255,255,0.06)',
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: theme.stroke,
    alignItems: 'center',
    justifyContent: 'center',
  },
  latched: { backgroundColor: 'rgba(255,255,255,0.95)' },
  label: { fontSize: 13, fontWeight: '600' },
});

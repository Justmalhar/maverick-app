/** Thin surface/card primitives that apply the Maverick dark tokens. */
import { ReactNode } from 'react';
import { StyleSheet, Text, TextStyle, View, ViewStyle } from 'react-native';
import { radius, space, theme } from '../theme';

export function Card({
  children,
  style,
}: {
  children: ReactNode;
  style?: ViewStyle;
}): React.JSX.Element {
  return <View style={[styles.card, style]}>{children}</View>;
}

export function Mono({
  children,
  color,
  size = 14,
  weight = '500',
  numberOfLines,
  style,
}: {
  children: ReactNode;
  color?: string;
  size?: number;
  weight?: TextStyle['fontWeight'];
  numberOfLines?: number;
  style?: TextStyle;
}): React.JSX.Element {
  return (
    <Text
      numberOfLines={numberOfLines}
      style={[
        { color: color ?? theme.textPrimary, fontSize: size, fontWeight: weight },
        style,
      ]}
    >
      {children}
    </Text>
  );
}

const styles = StyleSheet.create({
  card: {
    backgroundColor: theme.surface,
    borderRadius: radius.lg,
    borderWidth: 1,
    borderColor: theme.stroke,
    padding: space.lg,
  },
});

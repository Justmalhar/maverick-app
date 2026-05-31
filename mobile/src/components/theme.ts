/**
 * RN port of the Swift `Theme` palette (pure-monochrome Maverick Dark). Plain
 * constants so any component can pull a token without a provider. Excluded from
 * coverage (it is a static value bag consumed by the view components).
 */

export const theme = {
  bg: '#000000',
  bgElevated: '#0a0a0a',
  surface: '#0d0d10',
  surfaceHi: '#18181b',
  stroke: 'rgba(255,255,255,0.10)',
  strokeStrong: 'rgba(255,255,255,0.20)',
  textPrimary: '#fafafa',
  textSecondary: '#a1a1aa',
  textTertiary: '#52525b',
  accent: '#fafafa',
  onAccent: '#000000',
  danger: '#f87171',
  success: '#4ade80',
  info: '#60a5fa',
  warning: '#facc15',
} as const;

export const radius = { sm: 6, md: 10, lg: 14, pill: 999 } as const;
export const space = { xs: 4, sm: 8, md: 12, lg: 16, xl: 24 } as const;

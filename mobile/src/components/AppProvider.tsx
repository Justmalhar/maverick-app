/**
 * React context that exposes the single `AppModel` composition root to the
 * whole tree. The model is created once and persists for the app's lifetime.
 */

import { createContext, ReactNode, useContext, useMemo } from 'react';
import { AppModel } from '@/app/app-model';

const AppModelContext = createContext<AppModel | null>(null);

export function AppProvider({
  children,
  model,
}: {
  children: ReactNode;
  model?: AppModel;
}): React.JSX.Element {
  const value = useMemo(() => model ?? new AppModel(), [model]);
  return (
    <AppModelContext.Provider value={value}>{children}</AppModelContext.Provider>
  );
}

export function useApp(): AppModel {
  const model = useContext(AppModelContext);
  if (model === null) {
    throw new Error('useApp must be used within an AppProvider');
  }
  return model;
}

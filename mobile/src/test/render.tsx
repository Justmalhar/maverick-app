/**
 * Render helper that wraps a component in AppProvider with an injectable
 * AppModel whose client is a capturing fake. Excluded from coverage.
 */
import { ReactNode } from 'react';
import { render, RenderResult } from '@testing-library/react-native';
import { AppProvider } from '@/components/AppProvider';
import { AppModel } from '@/app/app-model';
import { MaverickClient } from '@/app/maverick-client';
import { ConnectionManager } from '@/net/connection-manager';
import { Transport, TransportHandlers } from '@/net/transports';

class SilentTransport implements Transport {
  readonly tier = 'lan' as const;
  state: 'closed' | 'opening' | 'open' = 'closed';
  open(h: TransportHandlers): void {
    this.state = 'open';
    h.onOpen();
  }
  send(): void {}
  close(): void {
    this.state = 'closed';
  }
}

export function makeAppModel(): AppModel {
  const manager = new ConnectionManager({
    transportFactory: () => new SilentTransport(),
  });
  const client = new MaverickClient(manager);
  const model = new AppModel({ client });
  client.connect({ host: 'test', port: 1 });
  return model;
}

export function renderWithApp(ui: ReactNode, model: AppModel): RenderResult {
  return render(<AppProvider model={model}>{ui}</AppProvider>);
}

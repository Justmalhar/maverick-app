import { AppSettings } from './app-settings';
import { MemoryStore } from './storage';

describe('AppSettings', () => {
  it('defaults to empty cwd and auto-reconnect on', () => {
    const s = new AppSettings(new MemoryStore());
    expect(s.lastWorkingDir).toBe('');
    expect(s.autoReconnect).toBe(true);
  });

  it('persists and reloads the working directory', () => {
    const store = new MemoryStore();
    const s = new AppSettings(store);
    let fired = 0;
    s.subscribe(() => fired++);
    s.setLastWorkingDir('  /Users/me/proj  ');
    expect(s.lastWorkingDir).toBe('/Users/me/proj');
    expect(fired).toBe(1);
    expect(new AppSettings(store).lastWorkingDir).toBe('/Users/me/proj');
  });

  it('is a no-op when the trimmed cwd is unchanged', () => {
    const s = new AppSettings(new MemoryStore());
    s.setLastWorkingDir('/x');
    let fired = 0;
    s.subscribe(() => fired++);
    s.setLastWorkingDir('  /x  ');
    expect(fired).toBe(0);
  });

  it('persists and reloads auto-reconnect', () => {
    const store = new MemoryStore();
    const s = new AppSettings(store);
    s.setAutoReconnect(false);
    expect(s.autoReconnect).toBe(false);
    expect(new AppSettings(store).autoReconnect).toBe(false);
    s.setAutoReconnect(false);
    s.setAutoReconnect(true);
    expect(s.autoReconnect).toBe(true);
  });
});

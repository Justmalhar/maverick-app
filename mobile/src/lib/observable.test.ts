import { Observable } from './observable';

class Probe extends Observable {
  fire(): void {
    this.notify();
  }
}

describe('Observable', () => {
  it('notifies subscribers and reports listener count', () => {
    const o = new Probe();
    expect(o.listenerCount).toBe(0);
    let count = 0;
    const unsub = o.subscribe(() => {
      count++;
    });
    expect(o.listenerCount).toBe(1);
    o.fire();
    o.fire();
    expect(count).toBe(2);
    unsub();
    expect(o.listenerCount).toBe(0);
    o.fire();
    expect(count).toBe(2);
  });

  it('bumps a monotonic version on each notify', () => {
    const o = new Probe();
    expect(o.version).toBe(0);
    o.fire();
    expect(o.version).toBe(1);
    o.fire();
    expect(o.version).toBe(2);
  });

  it('snapshots listeners so unsubscribe mid-emit is safe', () => {
    const o = new Probe();
    const seen: string[] = [];
    const unsubB = o.subscribe(() => seen.push('b'));
    o.subscribe(() => {
      seen.push('a');
      unsubB();
    });
    o.fire();
    expect(seen).toContain('a');
    expect(seen).toContain('b');
  });
});

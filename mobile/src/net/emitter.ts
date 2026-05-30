/** Tiny typed event emitter — no Node EventEmitter dependency (RN/web safe). */
export type Listener<T> = (value: T) => void;

export class Emitter<T> {
  private listeners = new Set<Listener<T>>();

  on(listener: Listener<T>): () => void {
    this.listeners.add(listener);
    return () => this.off(listener);
  }

  off(listener: Listener<T>): void {
    this.listeners.delete(listener);
  }

  emit(value: T): void {
    // Snapshot so a listener that unsubscribes mid-emit can't skip another.
    for (const listener of [...this.listeners]) listener(value);
  }

  get size(): number {
    return this.listeners.size;
  }

  clear(): void {
    this.listeners.clear();
  }
}

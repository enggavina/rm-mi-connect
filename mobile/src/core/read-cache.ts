/** Shares identical SQLite reads; retains only a bounded number of decoded rows. */
export class SharedReadCache<T> {
  private revision = -1;
  private entries = new Map<string, { promise: Promise<T[]>; size?: number }>();
  constructor(private maxEntries = 24, private maxRows = 3000) {}
  read(key: string, revision: number, load: () => Promise<T[]>): Promise<T[]> {
    if (revision !== this.revision) { this.entries.clear(); this.revision = revision; }
    const existing = this.entries.get(key);
    if (existing) {
      this.entries.delete(key); this.entries.set(key, existing);
      return existing.promise;
    }
    const entry: { promise: Promise<T[]>; size?: number } = { promise: Promise.resolve().then(load) };
    this.entries.set(key, entry);
    entry.promise = entry.promise.then(rows => {
      if (this.entries.get(key) === entry) {
        entry.size = rows.length;
        let total = [...this.entries.values()].reduce((sum, item) => sum + (item.size ?? 0), 0);
        for (const [oldKey, old] of this.entries) {
          if (total <= this.maxRows && this.entries.size <= this.maxEntries) break;
          if (old.size !== undefined) { total -= old.size; this.entries.delete(oldKey); }
        }
      }
      return rows;
    }, error => {
      if (this.entries.get(key) === entry) this.entries.delete(key);
      throw error;
    });
    return entry.promise;
  }
}

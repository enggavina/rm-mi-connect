export const MEDIA_CACHE_RESERVE_BYTES = 512 * 1024 * 1024;
export type MediaCachePause = 'low_space' | 'space_unavailable' | null;

/** Only background downloads are limited. The caller retains unfinished queue entries. */
export async function prefetchWithSpaceReserve<T>(items: readonly T[], freeStorage: () => Promise<number>, download: (item: T) => Promise<void>): Promise<MediaCachePause> {
  for (const item of items) {
    let freeBytes: number;
    try { freeBytes = await freeStorage(); } catch { return 'space_unavailable'; }
    if (!Number.isFinite(freeBytes) || freeBytes < 0) return 'space_unavailable';
    if (freeBytes <= MEDIA_CACHE_RESERVE_BYTES) return 'low_space';
    await download(item);
  }
  return null;
}

/** Keep bitmap-bearing screens bounded without dropping any matching records. */
export function pageItems<T>(items: readonly T[], requestedPage: number, pageSize: number) {
  const size = Math.max(1, Math.floor(pageSize));
  const pages = Math.max(1, Math.ceil(items.length / size));
  const page = Math.max(0, Math.min(pages - 1, Math.floor(requestedPage)));
  return { items: items.slice(page * size, (page + 1) * size), page, pages, total: items.length };
}

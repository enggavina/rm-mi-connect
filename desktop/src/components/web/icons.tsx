import type { CSSProperties } from 'react';
const paths = {
  dashboard: ['M3 3h7v7H3z', 'M14 3h7v7h-7z', 'M3 14h7v7H3z', 'M14 14h7v7h-7z'],
  folder: ['M3 7a2 2 0 0 1 2-2h5l2 2h7a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2Z'],
  board: ['M4 4h16v16H4z', 'M9 4v16', 'M15 4v16', 'M6 8h1', 'M11 12h2', 'M17 8h1'],
  calendar: ['M4 5h16v15H4z', 'M8 3v4', 'M16 3v4', 'M4 10h16', 'M8 14h3', 'M13 17h3'],
  clipboard: ['M9 4H5v17h14V4h-4', 'M9 3h6v4H9z', 'M8 12h8', 'M8 16h5'],
  settings: ['M12 8a4 4 0 1 0 0 8 4 4 0 0 0 0-8', 'm9 3-1 3-3 1-2 3 2 2-1 3 3 2 1 3h4l1-3 3-1 2-3-2-2 1-3-3-2-1-3Z'],
  arrow: ['M5 12h14', 'm13 6 6 6-6 6'], back: ['M19 12H5', 'm11 6-6 6 6 6'],
  external: ['M14 3h7v7', 'M10 14 21 3', 'M21 14v5a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h5'],
  chevron: ['m9 5 7 7-7 7'], search: ['M10.5 3a7.5 7.5 0 1 0 0 15 7.5 7.5 0 0 0 0-15', 'm16 16 5 5'],
  menu: ['M3 6h18', 'M3 12h18', 'M3 18h18'], close: ['m6 6 12 12', 'M18 6 6 18'],
  logout: ['M9 3H4v18h5', 'M9 12h12', 'm16 7 5 5-5 5'], refresh: ['M20 7v5h-5', 'M4 17v-5h5', 'M6 6a8 8 0 0 1 13 3', 'M18 18a8 8 0 0 1-13-3'],
  users: ['M9 3a4 4 0 1 0 0 8 4 4 0 0 0 0-8', 'M2 21v-3a5 5 0 0 1 5-5h4a5 5 0 0 1 5 5v3', 'M17 4a4 4 0 0 1 0 7', 'M18 14a5 5 0 0 1 4 4v3'],
  clock: ['M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20', 'M12 6v6l4 2'], image: ['M3 3h18v18H3z', 'm3 17 6-6 4 4 3-3 5 5', 'M8 7h.01'],
  file: ['M14 2H4v20h16V8Z', 'M14 2v6h6', 'M8 13h8', 'M8 17h6'], check: ['m4 12 5 5L20 6'], alert: ['m12 3 10 18H2Z', 'M12 9v5', 'M12 17h.01'],
  edit: ['m16 3 5 5-12 12-6 1 1-6Z', 'm13 6 5 5'], plus: ['M12 4v16', 'M4 12h16'], download: ['M12 3v12', 'm7 10 5 5 5-5', 'M3 16v5h18v-5'],
} as const;
export type IconName = keyof typeof paths;
export function Icon({ name, size = 20, style }: { name: IconName; size?: number; style?: CSSProperties }) {
  return <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true" focusable="false" style={style}>{paths[name].map((d, i) => <path key={i} d={d} />)}</svg>;
}

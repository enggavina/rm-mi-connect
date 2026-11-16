'use client';

import { useId } from 'react';
import styles from './mi-loader.module.css';

export function MiLoader({
  label = 'Entrando no EM…',
  compact = false,
}: {
  label?: string;
  compact?: boolean;
}) {
  const gradientId = `mi-loader-${useId().replace(/:/g, '')}`;

  return (
    <div
      className={`${styles.loader}${compact ? ` ${styles.compact}` : ''}`}
      role="status"
      aria-live="polite"
      aria-atomic="true"
    >
      <svg
        className={styles.symbol}
        viewBox="20.25 -32.85 256 256"
        width="148"
        height="148"
        aria-hidden="true"
        focusable="false"
      >
        <defs>
          <linearGradient
            id={`${gradientId}-left`}
            x1="53.1"
            y1="85.95"
            x2="206.99"
            y2="85.95"
            gradientUnits="userSpaceOnUse"
          >
            <stop offset="0" stopColor="#ae2f32" />
            <stop offset=".04" stopColor="#b23033" />
            <stop offset=".38" stopColor="#cf373b" />
            <stop offset=".68" stopColor="#e03c40" />
            <stop offset=".89" stopColor="#e73e42" />
          </linearGradient>
          <linearGradient
            id={`${gradientId}-right`}
            href={`#${gradientId}-left`}
            x1="89.51"
            y1="104.39"
            x2="243.4"
            y2="104.39"
            gradientUnits="userSpaceOnUse"
          />
        </defs>
        {/* Geometry and colors from public/mi-electric-brasil.svg. */}
        <g className={styles.arcs}>
          <path
            fill={`url(#${gradientId}-left)`}
            d="m148.25,4.07c21.03,0,40.41,7.17,55.85,19.18l2.9-2.9C190.81,7.61,170.4,0,148.25,0,95.79,0,53.1,42.69,53.1,95.15c0,18.53,5.34,35.83,14.55,50.47l-.12.26-12.23,26.01,17.93-17.93.16-.16s.04.06.07.09l2.9-2.9c-12.02-15.43-19.18-34.82-19.18-55.85,0-50.22,40.86-91.09,91.09-91.09Z"
          />
          <path
            fill={`url(#${gradientId}-right)`}
            d="m228.76,44.49l12.23-26.01-17.93,17.93-2.9,2.9c2.38,3.05,4.56,6.25,6.53,9.59,8.03,13.57,12.64,29.38,12.64,46.25,0,50.22-40.86,91.09-91.09,91.09-21.03,0-40.41-7.17-55.85-19.17l-2.9,2.9c16.19,12.74,36.59,20.35,58.74,20.35,52.47,0,95.15-42.68,95.15-95.15,0-18.61-5.37-35.99-14.64-50.66Z"
          />
        </g>
        <circle cx="148.25" cy="95.15" r="69.37" fill="#e73e42" />
        <g className={styles.letters} fill="#fff">
          <path d="m101.84,69.45h18.04l12.76,26.84,12.68-26.84h18.04v51.4h-14.88v-28.16l-10.34,23.17h-11.07l-10.34-23.17v28.16h-14.88v-51.4Z" />
          <path d="m177.65,69.45h17.01v51.4h-17.01v-51.4Z" />
        </g>
      </svg>
      <span className={styles.label}>{label}</span>
    </div>
  );
}

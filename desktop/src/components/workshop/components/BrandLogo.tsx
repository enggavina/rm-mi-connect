import type { CSSProperties } from 'react'

export interface BrandLogoProps {
  variant?: 'full' | 'symbol'
  tone?: 'original' | 'white'
  className?: string
  decorative?: boolean
  style?: CSSProperties
}

/** Original MI artwork, with lettering outlined and no external font dependency. */
export function BrandLogo({ variant = 'full', tone = 'original', className = '', decorative = false, style }: BrandLogoProps) {
  const symbol = variant === 'symbol'
  const asset = symbol ? 'mi-symbol' : 'mi-logo'
  return (
    <img
      className={`mi-brand-logo mi-brand-logo--${variant} ${className}`.trim()}
      src={`/workshop/brand/${asset}${tone === 'white' ? '-white' : ''}.svg`}
      alt={decorative ? '' : 'MI Electric Brasil'}
      aria-hidden={decorative || undefined}
      width={symbol ? 198.3 : 293}
      height={symbol ? 198.3 : 287.86}
      draggable={false}
      decoding="async"
      style={style}
    />
  )
}

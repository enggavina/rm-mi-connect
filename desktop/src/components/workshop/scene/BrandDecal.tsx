import { memo, Suspense, useEffect, useMemo } from 'react'
import { useTexture } from '@react-three/drei'
import { SRGBColorSpace } from 'three'
import type { Position3 } from '../domain/types'

export interface BrandDecalProps {
  src?: string
  position: Position3
  rotation?: Position3
  width?: number
}

const noRaycast = () => {}

function Artwork({ src = '/workshop/brand/mi-logo-white.svg', position, rotation = [0, 0, 0], width = 2 }: BrandDecalProps) {
  const original = useTexture(src)
  const texture = useMemo(() => {
    // Keep the loader's cached texture intact for other logo consumers.
    const clone = original.clone()
    clone.colorSpace = SRGBColorSpace
    clone.needsUpdate = true
    return clone
  }, [original])
  useEffect(() => () => texture.dispose(), [texture])
  const image = original.image as { naturalWidth?: number; naturalHeight?: number; width?: number; height?: number }
  const imageWidth = image.naturalWidth || image.width || 293
  const imageHeight = image.naturalHeight || image.height || 287.86

  return <mesh position={position} rotation={rotation} renderOrder={2} raycast={noRaycast}>
    <planeGeometry args={[width, width * imageHeight / imageWidth]} />
    <meshBasicMaterial map={texture} transparent depthWrite={false} toneMapped={false} polygonOffset polygonOffsetFactor={-1} polygonOffsetUnits={-1} />
  </mesh>
}

/** Transparent artwork on a +Z-facing plane. Place slightly ahead of its surface.
 * No background plate or geometry is added; SVG aspect ratio is preserved. */
export const BrandDecal = memo(function BrandDecal(props: BrandDecalProps) {
  return <Suspense fallback={null}><Artwork {...props} /></Suspense>
})

export default BrandDecal

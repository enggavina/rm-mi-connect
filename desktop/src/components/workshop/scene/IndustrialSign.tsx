import { memo, useEffect, useMemo } from 'react'
import { CanvasTexture, SRGBColorSpace } from 'three'
import type { Position3 } from '../domain/types'

interface IndustrialSignProps {
  text: string
  position: Position3
  size: [number, number]
  rotation?: Position3
  background?: string
  color?: string
  border?: string
}

/** Local, code-drawn wayfinding. The MI artwork itself always uses BrandDecal. */
export const IndustrialSign = memo(function IndustrialSign({ text, position, size, rotation = [0, 0, 0], background = '#f0f1ef', color = '#26333c', border }: IndustrialSignProps) {
  const texture = useMemo(() => {
    const canvas = document.createElement('canvas')
    canvas.width = 1024
    canvas.height = Math.max(128, Math.round(1024 * size[1] / size[0]))
    const context = canvas.getContext('2d')!
    context.fillStyle = background
    context.fillRect(0, 0, canvas.width, canvas.height)
    if (border) {
      context.strokeStyle = border
      context.lineWidth = Math.max(6, canvas.height * .055)
      context.strokeRect(7, 7, canvas.width - 14, canvas.height - 14)
    }
    context.fillStyle = color
    context.font = `700 ${Math.round(canvas.height * .53)}px Arial, sans-serif`
    context.textAlign = 'center'
    context.textBaseline = 'middle'
    context.fillText(text, canvas.width / 2, canvas.height * .53, canvas.width * .89)
    const result = new CanvasTexture(canvas)
    result.colorSpace = SRGBColorSpace
    return result
  }, [text, size[0], size[1], background, color, border])
  useEffect(() => () => texture.dispose(), [texture])
  return <mesh position={position} rotation={rotation}>
    <planeGeometry args={size} />
    <meshStandardMaterial map={texture} roughness={.88} metalness={.02} polygonOffset polygonOffsetFactor={-1} polygonOffsetUnits={-1} />
  </mesh>
})

export default IndustrialSign

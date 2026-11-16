import { memo, useEffect, useMemo } from 'react'
import { BufferGeometry, CanvasTexture, Float32BufferAttribute, SRGBColorSpace } from 'three'
import type { PcpCell } from '../data/layout'
import { getCellMapCode } from '../data/layout'

/** One texture atlas and one draw for all floor IDs; full names remain contextual. */
export default memo(function CellFloorMarkers({ cells }: { cells: PcpCell[] }) {
  const { texture, geometry } = useMemo(() => {
    const side = Math.ceil(Math.sqrt(cells.length)), tile = 96
    const canvas = document.createElement('canvas')
    canvas.width = canvas.height = side * tile
    const ctx = canvas.getContext('2d')!
    ctx.textAlign = 'center'; ctx.textBaseline = 'middle'; ctx.font = '700 48px Arial'
    const position: number[] = [], uv: number[] = []
    cells.forEach((cell, index) => {
      const col = index % side, row = Math.floor(index / side)
      ctx.fillStyle = '#46515b'; ctx.fillText(getCellMapCode(cell.id), col * tile + tile / 2, row * tile + tile / 2)
      const x = cell.position[0] - cell.size[0] / 2 + .65, z = cell.position[2] + cell.size[1] / 2 - .45, y = .109
      const w = .95, d = .68, u0 = col / side, u1 = (col + 1) / side, v0 = 1 - (row + 1) / side, v1 = 1 - row / side
      position.push(x-w/2,y,z-d/2, x-w/2,y,z+d/2, x+w/2,y,z+d/2, x-w/2,y,z-d/2, x+w/2,y,z+d/2, x+w/2,y,z-d/2)
      uv.push(u0,v1,u0,v0,u1,v0,u0,v1,u1,v0,u1,v1)
    })
    const geometry = new BufferGeometry()
    geometry.setAttribute('position', new Float32BufferAttribute(position, 3)); geometry.setAttribute('uv', new Float32BufferAttribute(uv, 2))
    geometry.computeVertexNormals()
    const texture = new CanvasTexture(canvas); texture.colorSpace = SRGBColorSpace
    return { geometry, texture }
  }, [cells])
  useEffect(() => () => { texture.dispose(); geometry.dispose() }, [texture, geometry])
  return <mesh geometry={geometry} raycast={() => {}} dispose={null}><meshBasicMaterial map={texture} transparent depthWrite={false} polygonOffset polygonOffsetFactor={-1}/></mesh>
})

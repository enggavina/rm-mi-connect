import { useMemo, useState } from 'react'
import type { CSSProperties } from 'react'
import { Html, useCursor } from '@react-three/drei'
import type { WorkshopOrder } from '../domain/types'
import { getCellSummaries, productionCells } from '../data/layout'
import type { PcpCell } from '../data/layout'
import { Box, BoxBatch } from './IndustrialModels'
import CellFloorMarkers from './CellFloorMarkers'
import './cells.css'

export interface ProductionCellsProps {
  orders: WorkshopOrder[]
  allOrders?: WorkshopOrder[]
  cells?: PcpCell[]
  selectedCellId: string | null
  onSelectCell: (id: string) => void
  highlighted?: boolean
  showLabels?: boolean
}

/** All catalog cells remain visible even when their active participation is 0.
 * This is a process map. Neither the floor zones nor their counters represent
 * measured physical occupancy or resource capacity. */
export default function ProductionCells({ orders, allOrders, cells = productionCells, selectedCellId, onSelectCell, highlighted = true, showLabels = false }: ProductionCellsProps) {
  const summaries = useMemo(() => getCellSummaries(allOrders ?? orders, cells), [allOrders, orders, cells])
  const [hoveredCell, setHoveredCell] = useState<string | null>(null)
  useCursor(hoveredCell !== null)
  return <group>
    <CellFloorMarkers cells={cells}/>
    {cells.map((cell, index) => {
      const summary = summaries[index]
      const selected = cell.id === selectedCellId
      const hovered = cell.id === hoveredCell
      const populated = summary.count > 0
      const width = cell.size[0], depth = cell.size[1]
      const border = selected ? '#ec3c44' : hovered ? '#53616e' : '#c5a747'
      const opacity = selected ? .22 : hovered ? .16 : populated && highlighted ? .1 : .035
      return <group key={cell.id} position={cell.position} onClick={event => { event.stopPropagation(); onSelectCell(cell.id) }} onPointerOver={event => { event.stopPropagation(); setHoveredCell(cell.id) }} onPointerOut={() => setHoveredCell(current => current === cell.id ? null : current)}>
        <mesh position={[0, .077, 0]} rotation={[-Math.PI / 2, 0, 0]} receiveShadow><planeGeometry args={[width, depth]} /><meshStandardMaterial color={cell.color} transparent opacity={opacity} depthWrite={false} roughness={1} /></mesh>
        <BoxBatch>
          {[-width / 2, width / 2].map(x => <Box key={`x${x}`} position={[x, .086, 0]} size={[selected ? .1 : .045, .018, depth]} color={border} />)}
          {[-depth / 2, depth / 2].map(z => <Box key={`z${z}`} position={[0, .086, z]} size={[width, .018, selected ? .1 : .045]} color={border} />)}
        </BoxBatch>
        {(showLabels || hovered || selected) && <Html position={[0, .22, depth / 2 - .25]} center zIndexRange={selected || hovered ? [10, 7] : [6, 2]} style={{ pointerEvents: showLabels ? 'auto' : 'none' }}>
          <button type="button" className={`pcp-cell-tag ${!showLabels ? 'is-contextual' : ''} ${selected ? 'is-selected' : ''} ${populated ? 'is-populated' : 'is-empty'}`} style={{ '--cell-color': cell.color, pointerEvents: showLabels ? 'auto' : 'none' } as CSSProperties} tabIndex={showLabels ? 0 : -1} data-cell-id={cell.id} onClick={event => { event.stopPropagation(); onSelectCell(cell.id) }} aria-pressed={selected} aria-label={`${cell.name}: ${summary.count} projetos em execução. Selecionar célula.`} title={`${cell.name} · ${summary.count} projetos em execução\nÁrea conceitual de processo; não representa localização física.`}>
            <span className="pcp-cell-dot" /><span className="pcp-cell-name">{hovered || selected ? cell.name : cell.shortName}</span><b>{summary.count}</b>
          </button>
        </Html>}
      </group>
    })}
  </group>
}

export { ProductionCells }

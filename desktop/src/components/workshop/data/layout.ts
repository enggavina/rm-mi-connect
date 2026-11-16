import type { Position3, WorkshopOrder, WorkshopResource } from '../domain/types'
import { calendarDay, getActiveStages, isOpenOrder } from '../domain/metrics'

export interface PcpCell {
  id: string
  name: string
  shortName: string
  color: string
  position: Position3
  size: [number, number]
  kind: 'work' | 'support' | 'storage' | 'logistics'
  group: string
  resourceId?: string
  sourceId?: string
  sourceOrder?: number | null
}
export interface CellCatalogEntry { id: string; name: string; order: number | null }

/** Mapa de processo, não levantamento arquitetônico. Toda geometria é
 * ilustrativa; as 29 denominações são do catálogo Bubble auditado. */
export const workshopBounds = {
  width: 56, depth: 36, height: 11.8,
  center: [0, 0, 0] as Position3,
  outerWidth: 72, outerDepth: 51,
}

const cell = (id: string, name: string, shortName: string, x: number, z: number, kind: PcpCell['kind'], group: string, color: string, resourceId?: string): PcpCell => ({
  id, name, shortName, position: [x, 0, z],
  size: kind === 'support' ? [6.8, 4.1] : kind === 'logistics' || kind === 'storage' ? [10.2, 4.4] : [6.6, 5.2],
  kind, group, color, resourceId: resourceId ?? `R-${id}`,
})

export const productionCells: PcpCell[] = [
  cell('relatorios-iniciais', 'Relatórios Iniciais', 'Rel. iniciais', -24, -13.7, 'support', 'Planejamento e apoio', '#84928b'),
  cell('double-check-peritagem', 'Double-check Peritagem', 'Double-check', -16, -13.7, 'support', 'Planejamento e apoio', '#84928b'),
  cell('orcamentos', 'Orçamentos', 'Orçamentos', -8, -13.7, 'support', 'Planejamento e apoio', '#8e9987'),
  cell('planejamento-materias', 'Planejamento de materias', 'Planej. materiais', 0, -13.7, 'support', 'Planejamento e apoio', '#8e9987'),
  cell('servicos-externos', 'Serviços externos', 'Serv. externos', 8, -13.7, 'support', 'Planejamento e apoio', '#8e9987'),
  cell('relatorios-reparo', 'Relatórios De Reparo', 'Rel. de reparo', 16, -13.7, 'support', 'Documentação', '#84928b'),
  cell('relatorios-finalizados', 'Relatórios De Reparo Finalizados', 'Rel. finalizados', 24, -13.7, 'support', 'Documentação', '#84928b'),
  cell('desmontagem', 'Desmontagem', 'Desmontagem', -22, -6.3, 'work', 'Inspeção e preparação', '#9e8b71', 'B-02'),
  cell('peritagem-mecanica', 'Peritagem Mecânica', 'Perit. mecânica', -13.2, -6.3, 'work', 'Inspeção e preparação', '#9e8b71'),
  cell('peritagem-eletrica', 'Peritagem Elétrica', 'Perit. elétrica', -4.4, -6.3, 'work', 'Inspeção e preparação', '#859b91', 'B-03'),
  cell('preparacao-pecas', 'Preparação de Peças', 'Prep. de peças', 4.4, -6.3, 'work', 'Inspeção e preparação', '#9e8b71'),
  cell('rebobinamento', 'Rebobinamento', 'Rebobinamento', 13.2, -6.3, 'work', 'Reparo e montagem', '#af9273', 'B-04'),
  cell('usinagem', 'Usinagem', 'Usinagem', 22, -6.3, 'work', 'Reparo e montagem', '#7892a1', 'B-09'),
  cell('manutencao-basica', 'Manutenção básica', 'Manut. básica', -22, 1, 'work', 'Reparo e montagem', '#859b91'),
  cell('caldeiraria', 'Caldeiraria', 'Caldeiraria', -13.2, 1, 'work', 'Reparo e montagem', '#9e8b71'),
  cell('balanceamento', 'Balanceamento', 'Balanceamento', -4.4, 1, 'work', 'Reparo e montagem', '#7892a1', 'S-01'),
  cell('ensaio-parcial', 'Ensaio Parcial', 'Ensaio parcial', 4.4, 1, 'work', 'Ensaios', '#7892a1'),
  cell('montagem', 'Montagem', 'Montagem', 13.2, 1, 'work', 'Reparo e montagem', '#779c89', 'B-06'),
  cell('acabamento', 'Acabamento', 'Acabamento', 22, 1, 'work', 'Finalização', '#a59674'),
  cell('peritagem-trafos', 'PERITAGEM DE TRAFOS', 'Perit. trafos', -22, 8.3, 'work', 'Transformadores', '#8e92a1'),
  cell('reparo-trafos', 'REPARO DE TRAFOS', 'Reparo trafos', -13.2, 8.3, 'work', 'Transformadores', '#8e92a1'),
  cell('peritagem-drives', 'Peritagem de Drives', 'Perit. drives', -4.4, 8.3, 'work', 'Drives', '#8294a1'),
  cell('reparo-drives', 'Reparo de Drives', 'Reparo drives', 4.4, 8.3, 'work', 'Drives', '#8294a1'),
  cell('testes-finais', 'Testes Finais', 'Testes finais', 13.2, 8.3, 'work', 'Ensaios', '#7892a1', 'E-01'),
  cell('pintura', 'Pintura', 'Pintura', 22, 8.3, 'work', 'Finalização', '#a59674'),
  cell('recebimento', 'Recebimento', 'Recebimento', -20, 15, 'logistics', 'Entrada e saída', '#a29369', 'B-01'),
  cell('estoque-equipamentos', 'Estoque de equipamentos', 'Estoque', -7, 15, 'storage', 'Entrada e saída', '#8a967d'),
  cell('motores-armazenados', 'MOTORES ARMAZENADOS', 'Armazenados', 7, 15, 'storage', 'Entrada e saída', '#8a967d'),
  cell('expedicao', 'Expedição', 'Expedição', 20, 15, 'logistics', 'Entrada e saída', '#a29369'),
]

/** Base floor IDs are permanent; added source cells use a plus, not a mutable ordinal. */
export function getCellMapCode(id: string): string {
  const index = productionCells.findIndex(cell => cell.id === id)
  return index < 0 ? '+' : String(index + 1).padStart(2, '0')
}

const compareIds = (left: string, right: string) => left < right ? -1 : left > right ? 1 : 0
const extraCellId = (sourceId: string) => `extra-${encodeURIComponent(sourceId)}`

/** Catalog order is not a physical coordinate. Existing bindings can be carried
 * between snapshots to retain an anchor when its source name changes. */
export function resolveProductionCells(catalog?: CellCatalogEntry[], previousCells: PcpCell[] = []): PcpCell[] {
  const resolved = productionCells.map(item => ({ ...item, position: [...item.position] as Position3, size: [...item.size] as [number, number] }))
  const previousBySourceId = new Map(previousCells.filter(item => item.sourceId).map(item => [item.sourceId!, item]))
  const reservedPositions = new Set((catalog ?? []).flatMap(entry => {
    const previous = previousBySourceId.get(entry.id)
    return previous && !productionCells.some(item => item.id === previous.id) ? [previous.position.join(',')] : []
  }))
  // Preserve previously established bindings before allocating new homonyms.
  const entries = [...(catalog ?? [])].sort((left, right) => Number(previousBySourceId.has(right.id)) - Number(previousBySourceId.has(left.id)) || compareIds(left.id, right.id))
  let extra = 0
  for (const entry of entries) {
    const name = entry.name.trim()
    const previous = previousBySourceId.get(entry.id)
    const known = previous
      ? resolved.find(item => item.id === previous.id && !item.sourceId)
      : resolved.find(item => item.name === name && !item.sourceId)
    if (known) {
      if (known.name !== name) known.shortName = name.length > 18 ? name.slice(0, 16) + '…' : name
      known.name = name; known.sourceId = entry.id; known.sourceOrder = entry.order
      continue
    }
    let position: Position3
    if (previous) position = [...previous.position]
    else {
      do { position = [33 + Math.floor(extra / 5) * 8, 0, -13 + extra % 5 * 6.5]; extra++ } while (reservedPositions.has(position.join(',')))
      reservedPositions.add(position.join(','))
    }
    resolved.push({
      id: previous?.id ?? extraCellId(entry.id), name, shortName: name.length > 18 ? name.slice(0, 16) + '…' : name,
      sourceId: entry.id, sourceOrder: entry.order, color: '#8b9b92', kind: 'support', group: 'Extensão do catálogo',
      position, size: [6.6, 5.2],
    })
  }
  return [...resolved.slice(0, productionCells.length), ...resolved.slice(productionCells.length).sort((left, right) => compareIds(left.id, right.id))]
}

export interface CellSummary { cellId: string; count: number; orderIds: string[] }
export function getCellSummaries(orders: WorkshopOrder[], cells: PcpCell[] = productionCells): CellSummary[] {
  const assignments = new Map(cells.map(item => [item.id, new Set<string>()]))
  const bySourceId = new Map(cells.filter(item => item.sourceId).map(item => [item.sourceId!, item.id]))
  const byName = new Map<string, string[]>()
  for (const item of cells) byName.set(item.name, [...(byName.get(item.name) ?? []), item.id])
  for (const order of orders) {
    if (!isOpenOrder(order)) continue
    const assignName = (name: string | null) => {
      const matches = name ? byName.get(name.trim()) : undefined
      // A duplicated name does not establish which source cell owns an activity.
      if (matches?.length === 1) assignments.get(matches[0])!.add(order.id)
    }
    if (order.activities !== undefined) {
      for (const activity of order.activities) {
        if (activity.status !== 'Executando' || calendarDay(activity.completedAt)) continue
        if (activity.cellId && bySourceId.size) {
          const id = bySourceId.get(activity.cellId)
          if (id) assignments.get(id)!.add(order.id)
          // An unresolved ID must not fall back to a homonymous source cell.
        } else assignName(activity.name)
      }
    } else getActiveStages(order).forEach(assignName)
  }
  return cells.map(item => { const orderIds = [...assignments.get(item.id)!]; return { cellId: item.id, count: orderIds.length, orderIds } })
}
export function getCellSummary(cell: PcpCell, orders: WorkshopOrder[]): CellSummary {
  return getCellSummaries(orders, [cell])[0]
}

const resource = (id: string, cellId: string, position?: Position3, kind: WorkshopResource['kind'] = 'bench', capacity: number | null = 1): WorkshopResource => {
  const area = productionCells.find(item => item.id === cellId)!
  return { id, name: id.startsWith('B-') ? `Bancada ${id.slice(2)}` : id.startsWith('E-') ? `Estação de ensaio ${id.slice(2)}` : id === 'S-01' ? 'Suporte de grandes rotores' : `Recurso ilustrativo · ${area.name}`, sector: area.name, position: position ?? [...area.position], rotation: 0, kind, capacity, illustrative: true }
}

/** capacity=1 is a demo setting; additional cells have no measured capacity. */
export const defaultResources: WorkshopResource[] = [
  resource('B-01', 'recebimento', [-20, 0, 14.4]),
  resource('B-02', 'desmontagem'),
  resource('B-03', 'peritagem-eletrica'),
  resource('B-04', 'rebobinamento', [11.5, 0, -6.3]),
  resource('B-05', 'rebobinamento', [14.9, 0, -6.3]),
  resource('B-06', 'montagem', [11.5, 0, .05]),
  resource('B-07', 'montagem', [14.9, 0, .05]),
  resource('B-08', 'montagem', [13.2, 0, 2.4]),
  resource('B-09', 'usinagem', [22, 0, -7.65]),
  resource('E-01', 'testes-finais', [11.5, 0, 8.3], 'test'),
  resource('E-02', 'testes-finais', [14.9, 0, 8.3], 'test'),
  resource('S-01', 'balanceamento', undefined, 'support'),
  ...productionCells.filter(item => item.resourceId?.startsWith('R-')).map(item => resource(item.resourceId!, item.id, undefined, item.id === 'ensaio-parcial' ? 'test' : 'bench', null)),
]

export const logisticsLayout = {
  roadZ: 23.5, roadWidth: 5,
  entrance: [-35, 0, 23.5] as Position3,
  exit: [35, 0, 23.5] as Position3,
  receiving: [-20, 0, 15] as Position3,
  stock: [-7, 0, 15] as Position3,
  stored: [7, 0, 15] as Position3,
  dispatch: [20, 0, 15] as Position3,
  unloading: [-20, 0, 23.5] as Position3,
  loading: [20, 0, 23.5] as Position3,
  mainAisleX: 0, aisleWidth: 2.2,
  crossAislesZ: [-10.2, -2.65, 4.65, 11.75],
}

export const workshopSectors = productionCells.filter(item => item.kind === 'work').map(item => ({ name: item.name, position: [item.position[0], .045, item.position[2]] as Position3, size: item.size, color: item.color }))

import type { PcpCell } from '../data/layout'
import type { Position3, WorkshopOrder, WorkshopResource } from './types'
import { calendarDay, getActiveStages, isOpenOrder } from './metrics'

export interface MotorPlacement {
  key: string; order: WorkshopOrder; position: Position3; rotation: number; unsupported: boolean; logical: boolean; cellId?: string; resourceId?: string; scale: number; copies: number
  unrepresentedReason?: 'no-running-stage' | 'unmapped-cell' | 'display-overflow' | 'unregistered-location'
  /** Top of the purely visual support, not a registered workshop resource. */
  supportHeight?: number
}

export const displayLimits = { cell: 6, support: 3, finalTests: 5 } as const
const visualSupportHeight = .14
const footDepth = { motor: .675, generator: .93, transformer: .73, drive: .955, rotor: .58, stator: .75, housing: .75, shaft: .22 } as const
export function getDisplayModelScale(order: WorkshopOrder, placementScale = 1): number {
  return (order.powerKw && order.powerKw >= 600 ? 1.13 : order.powerKw && order.powerKw < 90 ? .78 : 1) * placementScale
}
const supportedHeight = (order: WorkshopOrder, scale: number, supportHeight = visualSupportHeight) => supportHeight + footDepth[order.model] * getDisplayModelScale(order, scale)
export function partitionPlacements(placements: MotorPlacement[]): { representable: MotorPlacement[]; backlog: MotorPlacement[] } {
  return { representable: placements.filter(item => !item.unsupported), backlog: placements.filter(item => item.unsupported) }
}

/** Process coordinates are visual allocations; never write them back as physical locations. */
export function placeOrders(orders: WorkshopOrder[], resources: WorkshopResource[], cells: PcpCell[], mode: 'process' | 'physical', illustrativeOnly = false): MotorPlacement[] {
  let unlocated = 0
  const unallocatedX = Math.max(34, ...cells.map(cell => cell.position[0] + cell.size[0] / 2 + 5))
  const seen = new Map<string, number>()
  const bySourceId = new Map(cells.filter(cell => cell.sourceId).map(cell => [cell.sourceId!, cell.id]))
  const byName = new Map<string, PcpCell[]>()
  for (const cell of cells) byName.set(cell.name, [...(byName.get(cell.name) ?? []), cell])
  const processTargets = (order: WorkshopOrder): PcpCell[] => {
    if (!isOpenOrder(order)) return []
    const targets = new Set<string>()
    const resolveName = (name: string | null) => {
      const matches = name ? byName.get(name.trim()) : undefined
      // A label alone cannot identify one of two distinct source cells.
      if (matches?.length === 1) targets.add(matches[0].id)
    }
    if (order.activities !== undefined) {
      // Explicit activity records are authoritative over a display summary.
      // A completed period must not be revived by a stale activeStageNames.
      for (const activity of order.activities) {
        if (activity.status !== 'Executando' || calendarDay(activity.completedAt)) continue
        if (activity.cellId && bySourceId.size) {
          const target = bySourceId.get(activity.cellId)
          if (target) targets.add(target)
          // An unresolved source ID is not permission to match a homonym.
        } else resolveName(activity.name)
      }
    } else getActiveStages(order).forEach(resolveName)
    return cells.filter(cell => targets.has(cell.id))
  }
  const unknown = (order: WorkshopOrder, reason: MotorPlacement['unrepresentedReason']): MotorPlacement => {
    const index = unlocated++
    // Legacy coordinates remain only for contract compatibility. Unsupported
    // items belong in the DOM backlog and must not be rendered as physical stock.
    return { key: `${order.id}@unallocated`, order, position: [unallocatedX + Math.floor(index / 5) * 3.6, .88, -7 + index % 5 * 3.4], rotation: 0, unsupported: true, unrepresentedReason: reason, logical: mode === 'process', scale: 1, copies: 1 }
  }
  // Page/filter callers can select visible IDs after this complete projection.
  // Input arrival order must not decide which project occupies a visual slot.
  const ordered = [...orders].sort((left, right) => left.id < right.id ? -1 : left.id > right.id ? 1 : 0)
  return ordered.flatMap(order => {
    if (mode === 'process') {
      const targets = processTargets(order)
      if (!targets.length) {
        const hasRunningStage = order.activities !== undefined
          ? order.activities.some(activity => activity.status === 'Executando' && !calendarDay(activity.completedAt))
          : getActiveStages(order).length > 0
        return [unknown(order, hasRunningStage ? 'unmapped-cell' : 'no-running-stage')]
      }
      return targets.map(cell => {
        const index = seen.get(cell.id) ?? 0
        seen.set(cell.id, index + 1)
        const limit = cell.id === 'testes-finais' ? displayLimits.finalTests : cell.kind === 'support' ? displayLimits.support : displayLimits.cell
        if (index >= limit) return { ...unknown(order, 'display-overflow'), key: `${order.id}@${cell.id}`, cellId: cell.id, copies: targets.length }
        // The first test project uses the real visual rig; additional projects
        // stay on the left-hand display queue, clear of the rig and its crew.
        if (cell.id === 'testes-finais') {
          const queue = index - 1
          const scale = index === 0 ? .85 : .3, supportHeight = index === 0 ? .875 : .66
          return { key: `${order.id}@${cell.id}`, order, position: index === 0 ? [14.7, supportedHeight(order, scale, supportHeight), 7.8] as Position3 : [10.9 + queue % 2 * 1.2, supportedHeight(order, scale, supportHeight), 8.25 + Math.floor(queue / 2) * 1.25] as Position3, rotation: index === 0 ? Math.PI / 2 : 0, unsupported: false, logical: true, cellId: cell.id, scale, copies: targets.length, supportHeight }
        }
        // Six floor supports are a display limit, never measured cell capacity.
        const column = index % 3, row = Math.floor(index / 3)
        const rowOffset = cell.kind === 'support' ? (column === 1 ? -1.3 : 1.3) : (row === 0 ? -1 : 1) * (cell.kind === 'work' ? 1.8 : 1.4)
        return { key: `${order.id}@${cell.id}`, order, position: [cell.position[0] + (column - 1) * 2, supportedHeight(order, .48), cell.position[2] + rowOffset] as Position3, rotation: 0, unsupported: false, logical: true, cellId: cell.id, scale: .48, copies: targets.length, supportHeight: visualSupportHeight }
      })
    }
    const resource = illustrativeOnly ? undefined : resources.find(item => item.id === order.locationId)
    if (!resource) return [unknown(order, 'unregistered-location')]
    const index = seen.get(resource.id) ?? 0
    seen.set(resource.id, index + 1)
    if (index > 0) return [{ ...unknown(order, 'display-overflow'), key: `${order.id}@${resource.id}`, resourceId: resource.id }]
    const supportHeight = resource.position[1] + (resource.kind === 'bench' ? 1.105 : resource.kind === 'test' ? .8 : 1.1)
    return [{ key: `${order.id}@${resource.id}`, order, resourceId: resource.id, position: [resource.position[0], supportedHeight(order, 1, supportHeight), resource.position[2]] as Position3, rotation: resource.rotation, unsupported: false, logical: false, scale: 1, copies: 1, supportHeight }]
  })
}

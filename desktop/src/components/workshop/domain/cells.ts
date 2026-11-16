import type { WorkshopActivity, WorkshopOrder } from './types'
import { calendarDay, getActiveStages, isOpenOrder } from './metrics'

export interface CellIdentity { name: string; sourceId?: string }
export function isCurrentActivity(activity: WorkshopActivity) {
  return !calendarDay(activity.completedAt) && activity.status !== 'Finalizado' && activity.status !== 'N/A'
}
export function getCellWorkload(cell: CellIdentity, orders: WorkshopOrder[]) {
  const entries = orders.filter(isOpenOrder).flatMap(order => {
    const activities = order.activities?.filter(a => (cell.sourceId && a.cellId ? a.cellId === cell.sourceId : a.name?.trim() === cell.name) && isCurrentActivity(a)) ?? []
    // Activity identity and lifecycle outrank a display summary. Otherwise a
    // same-name cell, or an ended period, could appear as currently executing.
    const running = order.activities === undefined ? getActiveStages(order).includes(cell.name) : activities.some(a => a.status === 'Executando')
    if (!activities.length && !running) return []
    return [{ order, activities, running, waiting: activities.some(a => a.status !== 'Executando'), blocked: activities.length ? activities.some(a => a.blocked === true) : order.blockDeclared === true }]
  })
  return { entries, running: entries.filter(e => e.running).length, waiting: entries.filter(e => e.waiting).length, blocked: entries.filter(e => e.blocked).length }
}

import type { WorkshopOrder, ViewMode } from '../domain/types'
import { deadlineColors, statusColors } from '../domain/metrics'

export { deadlineColors } from '../domain/metrics'

export function getStageColor(stage: string | null): string {
  if (!stage) return statusColors.muted
  const colors = ['#548780', '#6886a2', '#9c7e5c', '#9b708a', '#7d915d', '#bb9250']
  const hash = [...stage].reduce((sum, char) => sum + char.charCodeAt(0), 0)
  return colors[hash % colors.length]
}

export function getOrderColor(order: WorkshopOrder, mode: ViewMode, deadline: keyof typeof deadlineColors): string {
  if (mode === 'deadlines') return deadlineColors[deadline]
  if (mode === 'stages') return getStageColor(order.stage)
  if (mode === 'blocks') return order.blockDeclared === true ? statusColors.danger : order.blockDeclared === false ? statusColors.success : statusColors.muted
  if (mode === 'capacity') return order.locationId ? statusColors.success : statusColors.muted
  return deadlineColors[deadline]
}

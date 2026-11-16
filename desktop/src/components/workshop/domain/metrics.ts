import type { DeadlineStatus, WorkshopOrder, WorkshopResource } from './types'

export const deadlineLabels: Record<DeadlineStatus, string> = { 'on-time': 'No prazo', soon: 'Prazo próximo', late: 'Atrasado', unknown: 'Sem previsão', complete: 'Entregue', canceled: 'Cancelado' }
// Mirrors the interface semantic tokens; shared by legends and scene markers.
export const statusColors = { success: '#26705b', warning: '#8a570c', danger: '#b92332', info: '#245f91', muted: '#5b6777' } as const
export const deadlineColors: Record<DeadlineStatus, string> = { 'on-time': statusColors.success, soon: statusColors.warning, late: statusColors.danger, unknown: statusColors.muted, complete: statusColors.info, canceled: statusColors.muted }
export const unknownStageLabel = 'Etapa não informada'
const normalize = (s: string) => s.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase().trim()
const workshopCalendar = new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Sao_Paulo', year: 'numeric', month: '2-digit', day: '2-digit' })

// Date.parse normalizes impossible dates such as February 30. Validate the
// source calendar first, and require an explicit offset for timestamp values.
export function isValidDateValue(value: string | null): boolean {
  if (!value) return false
  const match = /^(\d{4})-(\d{2})-(\d{2})(?:T([01]\d|2[0-3]):([0-5]\d):([0-5]\d)(?:\.\d{1,9})?(Z|[+-](?:0\d|1[0-4]):[0-5]\d))?$/.exec(value)
  if (!match) return false
  const year = Number(match[1]), month = Number(match[2]), day = Number(match[3])
  const leap = year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0)
  const monthDays = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
  if (year < 1 || month < 1 || month > 12 || day < 1 || day > monthDays[month - 1]) return false
  if (match[7]?.slice(1, 3) === '14' && match[7].slice(4) !== '00') return false
  return Number.isFinite(Date.parse(value))
}

// Date-only values already denote a civil day. Timestamps use the workshop
// timezone, never the timezone of the computer rendering the dashboard.
export function calendarDay(value: string | null): string | null {
  if (!isValidDateValue(value)) return null
  if (value!.length === 10) return value
  const parts = workshopCalendar.formatToParts(new Date(value!))
  return ['year', 'month', 'day'].map(k => parts.find(p => p.type === k)!.value.padStart(k === 'year' ? 4 : 2, '0')).join('-')
}
export function daysBetween(from: string | null, to: string | null): number | null {
  const a = calendarDay(from), b = calendarDay(to)
  return a && b ? Math.round((Date.parse(b + 'T12:00:00Z') - Date.parse(a + 'T12:00:00Z')) / 86400000) : null
}
export function isCanceledOrder(order: WorkshopOrder): boolean {
  return ['cancelado', 'cancelada'].includes(normalize(order.status ?? ''))
}
// Positive operational states observed in the PCP option set. Waiting/HOLD
// remain in the workshop only after an actual arrival has been recorded.
export const workshopActiveStatuses = [
  'Equipamento inspecionado', 'Executando', 'Aguardando aprovação', 'Revisão comercial',
  'Suspenso (HOLD)', 'Equipamento em inspeção', 'Sem previsão', 'Investigação de garantia', 'Executando com garantia',
] as const
const activeStatusKeys = new Set(workshopActiveStatuses.map(normalize))
export function isWorkshopActiveOrder(order: WorkshopOrder, referenceAt?: string): boolean {
  if (calendarDay(order.completedAt) || !activeStatusKeys.has(normalize(order.status ?? ''))) return false
  const arrival = calendarDay(order.enteredAt)
  if (!arrival) return false
  if (referenceAt !== undefined) {
    const reference = calendarDay(referenceAt)
    if (!reference || arrival > reference) return false
  }
  return true
}
export function isOpenOrder(order: WorkshopOrder): boolean {
  return isWorkshopActiveOrder(order)
}

export function getActiveStages(order: WorkshopOrder): string[] {
  if (!isOpenOrder(order)) return []
  let names: (string | null)[]
  if (order.activeStageNames !== undefined) names = order.activeStageNames
  else if (order.activities !== undefined) names = order.activities.filter(a => a.status === 'Executando' && !calendarDay(a.completedAt)).map(a => a.name)
  // Demo records omit activities. Real snapshots must declare the collection,
  // even when empty, so they never fall back to an arbitrary display stage.
  else names = [order.stage]
  return [...new Set(names.filter((name): name is string => typeof name === 'string' && !!name.trim()).map(name => name.trim()))]
}

export function getDeadlineStatus(order: WorkshopOrder, referenceAt: string, soonDays = 3): DeadlineStatus {
  if (isCanceledOrder(order)) return 'canceled'
  if (calendarDay(order.completedAt)) return 'complete'
  const days = daysBetween(referenceAt, order.dueAt)
  if (days === null) return 'unknown'
  const horizon = Number.isFinite(soonDays) ? Math.max(0, Math.floor(soonDays)) : 3
  return days < 0 ? 'late' : days <= horizon ? 'soon' : 'on-time'
}
export function formatDate(value: string | null, year = false): string {
  const day = calendarDay(value)
  if (!day) return 'Não informado'
  return new Intl.DateTimeFormat('pt-BR', { day: '2-digit', month: 'short', ...(year ? { year: 'numeric' as const } : {}), timeZone: 'UTC' }).format(new Date(day + 'T12:00:00Z')).replace('.', '')
}
export function formatTime(value: string) {
  if (!isValidDateValue(value)) return 'Não informado'
  return new Intl.DateTimeFormat('pt-BR', { hour: '2-digit', minute: '2-digit', timeZone: 'America/Sao_Paulo' }).format(new Date(value))
}
export function getMetrics(orders: WorkshopOrder[], referenceAt: string) {
  const open = orders.filter(order => isWorkshopActiveOrder(order, referenceAt))
  const canceled = orders.filter(isCanceledOrder)
  const completed = orders.filter(o => !isCanceledOrder(o) && calendarDay(o.completedAt) !== null)
  const durations = completed.map(o => daysBetween(o.enteredAt, o.completedAt)).filter((d): d is number => d !== null && d >= 0)
  const stages = new Map<string, number>()
  for (const order of open) {
    const names = getActiveStages(order)
    for (const name of names.length ? names : [unknownStageLabel]) stages.set(name, (stages.get(name) ?? 0) + 1)
  }
  return {
    open: open.length,
    completed: completed.length,
    canceled: canceled.length,
    late: open.filter(o => getDeadlineStatus(o, referenceAt) === 'late').length,
    blocked: open.filter(o => o.blockDeclared === true).length,
    unknownBlocks: open.filter(o => o.blockDeclared === null).length,
    noDeadline: open.filter(o => !calendarDay(o.dueAt)).length,
    upcoming: open.filter(o => { const d = daysBetween(referenceAt, o.dueAt); return d !== null && d >= 0 && d <= 7 }).length,
    leadTime: durations.length ? durations.reduce((a, b) => a + b, 0) / durations.length : null,
    leadTimeSample: durations.length,
    stages: Array.from(stages, ([name, count]) => ({ name, count })).sort((a, b) => b.count - a.count || a.name.localeCompare(b.name, 'pt-BR')),
  }
}
export function getOccupancy(orders: WorkshopOrder[], resources: WorkshopResource[], allowIllustrative: boolean, referenceAt?: string) {
  const known = resources.filter(r => r.capacity !== null && (allowIllustrative || !r.illustrative))
  const allocated = orders.filter(o => isWorkshopActiveOrder(o, referenceAt) && o.locationId && (allowIllustrative || o.locationVerified) && known.some(r => r.id === o.locationId))
  const occupied = new Set(allocated.map(o => o.locationId)).size
  return { occupied, total: known.length, slots: known.reduce((n, r) => n + (r.capacity ?? 0), 0), allocated: allocated.length }
}
export interface Filters { query: string; stage: string; client: string; responsible: string; period: string; onlyBlocked: boolean }
export const emptyFilters: Filters = { query: '', stage: '', client: '', responsible: '', period: '', onlyBlocked: false }
export function filterOrders(orders: WorkshopOrder[], filters: Filters, referenceAt: string) {
  return orders.filter(o => {
    if (!isWorkshopActiveOrder(o, referenceAt)) return false
    if (filters.query && !normalize([o.code, o.equipment, o.client, o.serial, o.responsible].join(' ')).includes(normalize(filters.query))) return false
    const stages = getActiveStages(o)
    if (filters.stage && (filters.stage === unknownStageLabel ? !isOpenOrder(o) || stages.length > 0 : !stages.includes(filters.stage))) return false
    if (filters.client && o.client !== filters.client) return false
    if (filters.responsible && o.responsible !== filters.responsible) return false
    if (filters.onlyBlocked && (!isOpenOrder(o) || o.blockDeclared !== true)) return false
    const days = daysBetween(referenceAt, o.dueAt)
    if (filters.period && !isOpenOrder(o)) return false
    if (filters.period === 'late' && (days === null || days >= 0)) return false
    if (filters.period === '7' && (days === null || days < 0 || days > 7)) return false
    if (filters.period === '30' && (days === null || days < 0 || days > 30)) return false
    if (filters.period === 'unknown' && days !== null) return false
    return true
  })
}

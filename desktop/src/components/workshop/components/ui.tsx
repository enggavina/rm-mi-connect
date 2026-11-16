import type { ButtonHTMLAttributes, ReactNode } from 'react'
import type { WorkshopOrder } from '../domain/types'
import { deadlineLabels, getDeadlineStatus } from '../domain/metrics'
export function IconButton({ label, children, ...props }: ButtonHTMLAttributes<HTMLButtonElement> & { label: string; children: ReactNode }) {
  return <button type="button" title={label} aria-label={label} {...props} className={`icon-button ${props.className ?? ''}`}>{children}</button>
}
export function StatusBadge({ order, at, soonDays }: { order: WorkshopOrder; at: string; soonDays: number }) {
  const status = getDeadlineStatus(order, at, soonDays)
  return <span className={`status-badge ${status}`}><i />{deadlineLabels[status]}</span>
}
export function EmptyState({ title, children }: { title: string; children: ReactNode }) {
  return <div className="empty-state"><span className="empty-orbit">◎</span><h3>{title}</h3><p>{children}</p></div>
}

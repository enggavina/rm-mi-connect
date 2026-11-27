import type { PcpCell } from '../data/layout'

export type ViewMode = 'overview' | 'stages' | 'deadlines' | 'blocks' | 'capacity'
export type DeadlineStatus = 'on-time' | 'soon' | 'late' | 'unknown' | 'complete' | 'canceled'
export type ModelKind = 'motor' | 'generator' | 'transformer' | 'drive' | 'rotor' | 'stator' | 'housing' | 'shaft'
export type Position3 = [number, number, number]
export interface WorkshopActivity {
  id: string
  cellId?: string | null
  name: string | null
  status: string | null
  blocked: boolean | null
  blockReason: string | null
  startedAt: string | null
  dueAt: string | null
  completedAt: string | null
  responsible: string | null
}
export interface WorkshopOrder {
  id: string
  code: string
  equipment: string
  client: string | null
  stage: string | null
  status: string | null
  responsible: string | null
  enteredAt: string | null
  dueAt: string | null
  completedAt: string | null
  blockReason: string | null
  blockDeclared: boolean | null
  priority: string | null
  powerKw: number | null
  rpm: number | null
  serial: string | null
  locationId: string | null
  locationVerified: boolean
  model: ModelKind
  equipmentType?: string | null
  modelVerified?: boolean
  sourceUrl: string | null
  history: { at: string; label: string }[]
  activities?: WorkshopActivity[]
  activeStageNames?: string[]
  dueSource?: string | null
  powerRaw?: string | null
  rpmRaw?: string | null
}
export interface WorkshopResource {
  id: string
  name: string
  sector: string
  position: Position3
  rotation: number
  kind: 'bench' | 'support' | 'test'
  capacity: number | null
  illustrative: boolean
}
export interface WorkshopSnapshot {
  schemaVersion: 1
  source: 'supabase'
  fetchedAt: string
  referenceAt: string
  orders: WorkshopOrder[]
  resources: WorkshopResource[]
  warnings: string[]
  cells?: WorkshopCell[]
  layout?: 'bma' | 'management'
}
export interface WorkshopCell { id: string; name: string; order: number | null }
export type RoofMode = 'hidden' | 'translucent' | 'closed'
export interface SceneLayers { architecture: boolean; roof: boolean; roofMode?: RoofMode; labels: boolean; areaLabels: boolean; sectors: boolean; cranes: boolean }
export type BooleanSceneLayer = Exclude<keyof SceneLayers, 'roofMode'>
export interface SceneProps {
  illustrativeOnly?: boolean
  placementMode?: 'process' | 'physical'
  catalog?: WorkshopCell[]
  allOrders?: WorkshopOrder[]
  /** Full active cohort, before UI filters: keeps visual slots stable. */
  layoutOrders?: WorkshopOrder[]
  resolvedCells?: PcpCell[]
  selectedCellId?: string | null
  onSelectCell?: (id: string) => void
  animationRunning?: boolean
  showWorkers?: boolean
  showLogistics?: boolean
  orders: WorkshopOrder[]
  resources: WorkshopResource[]
  selectedId: string | null
  selectedResourceId: string | null
  onSelect: (id: string | null) => void
  onSelectResource: (id: string) => void
  mode: ViewMode
  layers: SceneLayers
  referenceAt: string
  soonDays: number
  cameraCommand: { type: 'reset' | 'focus' | 'zoom-in' | 'zoom-out' | 'rotate'; seq: number }
  onReady?: () => void
  onUnavailable?: () => void
}

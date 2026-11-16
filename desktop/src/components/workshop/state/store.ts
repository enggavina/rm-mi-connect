import { create } from 'zustand'
import { persist } from 'zustand/middleware'
import type { BooleanSceneLayer, RoofMode, SceneLayers, SceneProps, ViewMode } from '../domain/types'
import { emptyFilters, type Filters } from '../domain/metrics'
interface Store {
  mode: ViewMode; page: 'workshop' | 'management' | 'source'; layers: SceneLayers; soonDays: number; filters: Filters;
  selectedId: string | null; selectedResourceId: string | null; cameraCommand: SceneProps['cameraCommand'];
  selectedCellId: string | null; placementMode: 'process' | 'physical'; animationRunning: boolean; showWorkers: boolean; showLogistics: boolean;
  selectCell: (id: string | null) => void; setPlacementMode: (mode: 'process' | 'physical') => void; toggleAnimation: () => void; toggleWorkers: () => void; toggleLogistics: () => void;
  setMode: (mode: ViewMode) => void; setPage: (page: Store['page']) => void; toggleLayer: (key: BooleanSceneLayer) => void; setRoofMode: (mode: RoofMode) => void; setSoonDays: (n: number) => void;
  setFilter: <K extends keyof Filters>(key: K, value: Filters[K]) => void; resetFilters: () => void;
  select: (id: string | null) => void; selectResource: (id: string) => void; camera: (type: SceneProps['cameraCommand']['type']) => void;
}
export const useWorkshop = create<Store>()(persist((set) => ({
  mode: 'overview', page: 'workshop', soonDays: 3,
  layers: { architecture: true, roof: false, roofMode: 'hidden', labels: false, areaLabels: false, sectors: true, cranes: true }, filters: { ...emptyFilters }, selectedId: null, selectedResourceId: null, cameraCommand: { type: 'reset', seq: 0 },
  selectedCellId: null, placementMode: 'process', animationRunning: true, showWorkers: true, showLogistics: true,
  selectCell: selectedCellId => set({ selectedCellId, selectedId: null, selectedResourceId: null }),
  setPlacementMode: placementMode => set(s => ({ placementMode, cameraCommand: { type: 'reset', seq: s.cameraCommand.seq + 1 } })),
  toggleAnimation: () => set(s => ({ animationRunning: !s.animationRunning })), toggleWorkers: () => set(s => ({ showWorkers: !s.showWorkers })), toggleLogistics: () => set(s => ({ showLogistics: !s.showLogistics })),
  setMode: mode => set({ mode }), setPage: page => set({ page }), toggleLayer: key => set(s => ({ layers: { ...s.layers, [key]: !s.layers[key], ...(key === 'roof' ? { roofMode: s.layers.roof ? 'hidden' : 'translucent' } : {}) } })),
  setRoofMode: roofMode => set(s => ({ layers: { ...s.layers, roofMode, roof: roofMode !== 'hidden' } })),
  setSoonDays: n => set({ soonDays: Math.min(30, Math.max(0, Math.round(n))) }),
  setFilter: (key, value) => set(s => ({ filters: { ...s.filters, [key]: value } })), resetFilters: () => set({ filters: { ...emptyFilters } }),
  select: selectedId => set({ selectedId, selectedResourceId: null, selectedCellId: null }), selectResource: selectedResourceId => set({ selectedResourceId, selectedId: null, selectedCellId: null }),
  camera: type => set(s => ({ cameraCommand: { type, seq: s.cameraCommand.seq + 1 } })),
}), {
  name: 'em-workshop-preferences-v1',
  partialize: state => ({ layers: state.layers, soonDays: state.soonDays }),
  merge: (persisted, current) => {
    const saved = persisted as Partial<Pick<Store, 'layers' | 'soonDays'>> | undefined
    // Older saved layer settings do not contain the new area-label preference.
    const roofMode = saved?.layers?.roofMode
    return { ...current, soonDays: saved?.soonDays ?? current.soonDays, layers: { ...current.layers, ...saved?.layers, roofMode: roofMode === 'closed' || roofMode === 'translucent' || roofMode === 'hidden' ? roofMode : saved?.layers?.roof ? 'translucent' : 'hidden' } }
  },
}))

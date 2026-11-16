/** Illustrative crane choreography; independent from operational records. */
export const craneTravel = { bridgeX: 21, trolleyZ: 11, minDrop: 1.35, maxDrop: 3.25, period: 192 } as const
export interface CranePose { bridgeX: number; trolleyZ: number; hookDrop: number }
export interface CraneClock { elapsed: number; primed: boolean }
export interface CraneClockState { running: boolean; visible: boolean; reducedMotion: boolean }

export function getCranePose(elapsed: number): CranePose {
  const time = Number.isFinite(elapsed) ? Math.max(0, elapsed) % craneTravel.period : 0
  return {
    bridgeX: craneTravel.bridgeX * Math.sin(time * Math.PI * 2 / 96),
    trolleyZ: craneTravel.trolleyZ * Math.sin(time * Math.PI * 2 / 64 + .35),
    hookDrop: 2.3 + .95 * Math.cos(time * Math.PI * 2 / 48),
  }
}

/** Pausing/hidden tabs/reduced motion keep the exact pose. The first resumed
 * frame is discarded so idle wall-clock time never becomes a visual jump. */
export function advanceCraneClock(clock: CraneClock, delta: number, state: CraneClockState): CraneClock {
  if (!state.running || !state.visible || state.reducedMotion) return { elapsed: clock.elapsed, primed: false }
  if (!clock.primed) return { elapsed: clock.elapsed, primed: true }
  return { elapsed: clock.elapsed + (Number.isFinite(delta) ? Math.min(.05, Math.max(0, delta)) : 0), primed: true }
}

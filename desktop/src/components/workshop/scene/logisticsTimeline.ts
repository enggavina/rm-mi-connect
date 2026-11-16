/**
 * Choreography only: no connection to WorkshopOrder, source records or employee
 * identities. Coordinates are an illustrative plan agreed with Architecture.
 * Trucks use the exterior lane; forklifts use the clear frontage and dock bays.
 */
export type PlanarPoint = readonly [x: number, z: number]
export interface RoutePose { x: number; z: number; yaw: number }
export interface Route {
  points: PlanarPoint[]
  distances: number[]
  length: number
}
const clamp = (value: number) => Math.max(0, Math.min(1, Number.isFinite(value) ? value : 0))
export const ease = (value: number) => { const t = clamp(value); return t * t * (3 - 2 * t) }
const distance = (a: PlanarPoint, b: PlanarPoint) => Math.hypot(b[0] - a[0], b[1] - a[1])
const pointBetween = (a: PlanarPoint, b: PlanarPoint, t: number): PlanarPoint => [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t]

/** Round corners inside their bounding box; never overshoot into another bay. */
export function createRoute(input: readonly PlanarPoint[], radius = .55): Route {
  if (!input.length || input.some(p => p.length !== 2 || !p.every(Number.isFinite))) throw new Error('Rota ilustrativa inválida')
  const original = input.filter((p, i) => !i || distance(p, input[i - 1]) > .00001)
  const points: PlanarPoint[] = [original[0]]
  for (let i = 1; i < original.length - 1; i++) {
    const previous = original[i - 1], corner = original[i], next = original[i + 1]
    const incoming = distance(previous, corner), outgoing = distance(corner, next)
    const cut = Math.min(Math.max(0, radius), incoming / 3, outgoing / 3)
    const entry = pointBetween(corner, previous, cut / incoming), exit = pointBetween(corner, next, cut / outgoing)
    points.push(entry)
    for (let step = 1; step <= 10; step++) {
      const t = step / 10, a = pointBetween(entry, corner, t), b = pointBetween(corner, exit, t)
      points.push(pointBetween(a, b, t))
    }
  }
  if (original.length > 1) points.push(original[original.length - 1])
  const clean = points.filter((p, i) => !i || distance(p, points[i - 1]) > .00001)
  const distances = [0]
  for (let i = 1; i < clean.length; i++) distances.push(distances[i - 1] + distance(clean[i - 1], clean[i]))
  return { points: clean, distances, length: distances[distances.length - 1] }
}
const heading = (a: PlanarPoint, b: PlanarPoint) => Math.atan2(b[0] - a[0], b[1] - a[1])
const blendAngle = (a: number, b: number, t: number) => a + Math.atan2(Math.sin(b - a), Math.cos(b - a)) * t

/** Constant distance along the route; progress easing belongs to the phase. */
export function sampleRoute(route: Route, progress: number, reverse = false): RoutePose {
  const target = route.length * clamp(progress)
  if (route.points.length === 1) return { x: route.points[0][0], z: route.points[0][1], yaw: reverse ? Math.PI : 0 }
  let index = 1
  while (index < route.points.length - 1 && route.distances[index] < target) index++
  const a = route.points[index - 1], b = route.points[index]
  const t = (target - route.distances[index - 1]) / (route.distances[index] - route.distances[index - 1])
  const startHeading = index > 1 ? heading(route.points[index - 2], b) : heading(a, b)
  const endHeading = index < route.points.length - 1 ? heading(a, route.points[index + 1]) : heading(a, b)
  const position = pointBetween(a, b, t)
  return { x: position[0], z: position[1], yaw: blendAngle(startHeading, endHeading, t) + (reverse ? Math.PI : 0) }
}

export const logisticsRoutes = {
  incomingTruck: createRoute([[-37, 23.5], [-20, 23.5]]),
  incomingExit: createRoute([[-20, 23.5], [37, 23.5]]),
  incomingApproach: createRoute([[-20, 18.5], [-21.2, 18.5], [-21.2, 21.3]]),
  incomingReverse: createRoute([[-21.2, 21.3], [-21.2, 18.5]]),
  toStock: createRoute([[-21.2, 18.5], [-7, 18.5], [-7, 17.15]]),
  stockReverse: createRoute([[-7, 17.15], [-7, 18.5]]),
  incomingReturn: createRoute([[-7, 18.5], [-20, 18.5]]),
  outgoingTruck: createRoute([[37, 23.5], [20, 23.5]]),
  outgoingExit: createRoute([[20, 23.5], [-37, 23.5]]),
  outgoingFetch: createRoute([[24, 18.5], [20, 18.5], [20, 17.15]]),
  dispatchReverse: createRoute([[20, 17.15], [20, 18.5]]),
  toOutgoingTruck: createRoute([[20, 18.5], [21.2, 18.5], [21.2, 21.3]]),
  outgoingReverse: createRoute([[21.2, 21.3], [21.2, 18.5]]),
  outgoingReturn: createRoute([[21.2, 18.5], [24, 18.5]]),
} as const

export const logisticsPhases = [
  { name: 'recebimento-chegada', duration: 12 },
  { name: 'recebimento-aproximacao', duration: 8 },
  { name: 'recebimento-descarga', duration: 4 },
  { name: 'recebimento-recuo', duration: 5 },
  { name: 'recebimento-ao-estoque', duration: 15 },
  { name: 'estoque-deposito', duration: 4 },
  { name: 'estoque-recuo', duration: 4 },
  { name: 'recebimento-retorno', duration: 12 },
  { name: 'recebimento-saida', duration: 12 },
  { name: 'expedicao-chegada', duration: 12 },
  { name: 'expedicao-coleta', duration: 8 },
  { name: 'expedicao-elevar', duration: 4 },
  { name: 'expedicao-recuo', duration: 5 },
  { name: 'expedicao-ao-caminhao', duration: 15 },
  { name: 'expedicao-carga', duration: 4 },
  { name: 'expedicao-afastamento', duration: 4 },
  { name: 'expedicao-retorno', duration: 6 },
  { name: 'expedicao-saida', duration: 12 },
] as const
export type LogisticsPhase = typeof logisticsPhases[number]['name']
export const LOGISTICS_CYCLE_SECONDS = logisticsPhases.reduce((sum, phase) => sum + phase.duration, 0)

export function phaseAt(seconds: number) {
  const safe = Number.isFinite(seconds) ? Math.max(0, seconds) : 0
  const time = safe % LOGISTICS_CYCLE_SECONDS
  let start = 0
  for (let index = 0; index < logisticsPhases.length; index++) {
    const phase = logisticsPhases[index]
    if (time < start + phase.duration) return { name: phase.name, index, progress: (time - start) / phase.duration, time }
    start += phase.duration
  }
  return { name: logisticsPhases[0].name, index: 0, progress: 0, time: 0 }
}
export interface FlowFrame {
  truck: RoutePose
  truckVisible: boolean
  truckLoaded: boolean
  forklift: RoutePose
  forkHeight: number
  forkLoaded: boolean
  depotLoaded: boolean
}
export interface LogisticsFrame {
  phase: LogisticsPhase
  incoming: FlowFrame
  outgoing: FlowFrame
}
const fixed = (x: number, z: number, yaw: number): RoutePose => ({ x, z, yaw })
const mix = (from: number, to: number, t: number) => from + (to - from) * ease(t)

/** Sequential freight cycles prevent the two trucks sharing the same lane. */
export function logisticsFrame(seconds: number): LogisticsFrame {
  const phase = phaseAt(seconds), i = phase.index, p = ease(phase.progress), routes = logisticsRoutes
  const incoming: FlowFrame = {
    truck: fixed(-20, 23.5, Math.PI / 2), truckVisible: i <= 8, truckLoaded: i < 2 || i === 2 && phase.progress < .5,
    forklift: fixed(-20, 18.5, -Math.PI / 2), forkHeight: .35, forkLoaded: i >= 3 && i <= 5 || i === 2 && phase.progress >= .5,
    depotLoaded: i >= 6,
  }
  if (i === 0) incoming.truck = sampleRoute(routes.incomingTruck, p)
  if (i === 1) { incoming.forklift = sampleRoute(routes.incomingApproach, p); incoming.forkHeight = mix(.35, 1.08, phase.progress) }
  if (i === 2) { incoming.forklift = fixed(-21.2, 21.3, 0); incoming.forkHeight = mix(1.08, 1.17, phase.progress) }
  if (i === 3) { incoming.forklift = sampleRoute(routes.incomingReverse, p, true); incoming.forkHeight = mix(1.17, .35, phase.progress) }
  if (i === 4) incoming.forklift = sampleRoute(routes.toStock, p)
  if (i === 5) { incoming.forklift = fixed(-7, 17.15, Math.PI); incoming.forkHeight = mix(.35, .01, phase.progress) }
  if (i === 6) { incoming.forklift = sampleRoute(routes.stockReverse, p, true); incoming.forkHeight = .01 }
  if (i === 7) { incoming.forklift = sampleRoute(routes.incomingReturn, p); incoming.forkHeight = mix(.01, .35, phase.progress) }
  if (i === 8) incoming.truck = sampleRoute(routes.incomingExit, p)
  const outgoing: FlowFrame = {
    truck: fixed(20, 23.5, -Math.PI / 2), truckVisible: i >= 9, truckLoaded: i >= 15,
    forklift: fixed(24, 18.5, Math.PI / 2), forkHeight: .35,
    forkLoaded: i >= 12 && i <= 14 || i === 11 && phase.progress >= .15,
    depotLoaded: i < 11 || i === 11 && phase.progress < .15,
  }
  if (i === 9) outgoing.truck = sampleRoute(routes.outgoingTruck, p)
  if (i === 10) { outgoing.forklift = sampleRoute(routes.outgoingFetch, p); outgoing.forkHeight = mix(.35, .01, phase.progress) }
  if (i === 11) { outgoing.forklift = fixed(20, 17.15, Math.PI); outgoing.forkHeight = mix(.01, .35, phase.progress) }
  if (i === 12) outgoing.forklift = sampleRoute(routes.dispatchReverse, p, true)
  if (i === 13) outgoing.forklift = sampleRoute(routes.toOutgoingTruck, p)
  if (i === 14) { outgoing.forklift = fixed(21.2, 21.3, 0); outgoing.forkHeight = mix(.35, 1.08, phase.progress) }
  if (i === 15) { outgoing.forklift = sampleRoute(routes.outgoingReverse, p, true); outgoing.forkHeight = mix(1.08, .35, phase.progress) }
  if (i === 16) outgoing.forklift = sampleRoute(routes.outgoingReturn, p)
  if (i === 17) outgoing.truck = sampleRoute(routes.outgoingExit, p)
  return { phase: phase.name, incoming, outgoing }
}

export const workerRoutes = [
  createRoute([[0, -9], [0, 10]]),
  createRoute([[-24, -2.65], [-3, -2.65]]),
] as const
/** Both pedestrian routes occupy separate aisles and never intersect each other. */
export function walkingWorkerFrame(seconds: number, index: number) {
  const route = workerRoutes[index % workerRoutes.length]
  const period = index % workerRoutes.length === 0 ? 54 : 62
  const t = ((Math.max(0, seconds) + index * 9) % period) / period
  const returning = t > .5
  const progress = ease(returning ? 2 - t * 2 : t * 2)
  const pose = sampleRoute(route, progress)
  if (returning) pose.yaw += Math.PI
  const walking = Math.min(1, Math.abs(Math.sin(t * Math.PI * 2)) * 3)
  return { ...pose, walking }
}

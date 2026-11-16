import { createRoute, sampleRoute } from './logisticsTimeline'
import type { PlanarPoint, Route, RoutePose } from './logisticsTimeline'

// Anonymous scenery. The pedestrian network never uses project or employee data.
// Nodes sit in the aisles between cells, away from the truck/forklift frontage.
export const pedestrianAisles = { x: [-26.4, -17.6, -8.8, 0, 8.8, 17.6, 26.4], z: [-10.2, -2.65, 4.65, 11.75] } as const
export const WALKING_STAFF_COUNT = 12
export const PEDESTRIAN_CLEARANCE = .8
const LANE_OFFSET = .42
const JUNCTION_RADIUS = 1.45
const JUNCTION_APPROACH = 1.15
export interface PedestrianPose extends RoutePose { walking: number; action: 'walking' | 'checking' | 'waiting' }
interface Pedestrian {
  seed: number; node: number; previous: number; route: Route; distance: number; speed: number; rest: number; trips: number; pose: PedestrianPose
}
export interface PedestrianSimulation { people: Pedestrian[]; elapsed: number; junctions: Map<number, number> }
function random(person: Pedestrian) {
  person.seed = (Math.imul(person.seed, 1664525) + 1013904223) >>> 0
  return person.seed / 4294967296
}
const coordinates = (node: number): PlanarPoint => [pedestrianAisles.x[node % 7], pedestrianAisles.z[Math.floor(node / 7)]]
const junctionAt = (point: RoutePose) => {
  for (let node = 0; node < 28; node++) {
    const [x, z] = coordinates(node)
    if (Math.hypot(point.x - x, point.z - z) <= JUNCTION_RADIUS) return node
  }
  return -1
}

/** Right-hand lanes are fixed by travel direction, never by the person's ID.
 * Turns join the two lane lines inside their intersection. Routes begin at the
 * exact previous endpoint, so replanning cannot teleport a resting person. */
function pedestrianRoute(nodes: number[], start: RoutePose): Route {
  const points: PlanarPoint[] = [[start.x, start.z]]
  for (let index = 0; index < nodes.length - 1; index++) {
    const a = coordinates(nodes[index]), b = coordinates(nodes[index + 1])
    const dx = Math.sign(b[0] - a[0]), dz = Math.sign(b[1] - a[1])
    const nx = dz * LANE_OFFSET, nz = -dx * LANE_OFFSET
    points.push([a[0] + dx * JUNCTION_APPROACH + nx, a[1] + dz * JUNCTION_APPROACH + nz])
    points.push([b[0] - dx * JUNCTION_APPROACH + nx, b[1] - dz * JUNCTION_APPROACH + nz])
    if (index < nodes.length - 2) {
      const next = coordinates(nodes[index + 2])
      const nextDx = Math.sign(next[0] - b[0]), nextDz = Math.sign(next[1] - b[1])
      if (dx !== nextDx || dz !== nextDz) points.push([b[0] + nx + nextDz * LANE_OFFSET, b[1] + nz - nextDx * LANE_OFFSET])
    }
  }
  points.push(coordinates(nodes[nodes.length - 1]))
  return createRoute(points, .24)
}
function planNext(person: Pedestrian) {
  const from = person.node
  let target = Math.floor(random(person) * 28)
  // Avoid a repeated shuttle between two points; vary destinations and turns.
  if (target === from || target === person.previous) target = (target + 9) % 28
  if (target === from) target = (target + 1) % 28
  let col = from % 7, row = Math.floor(from / 7)
  const targetCol = target % 7, targetRow = Math.floor(target / 7)
  const path = [from]
  const horizontalFirst = random(person) > .5
  const walkX = () => { while (col !== targetCol) { col += Math.sign(targetCol - col); path.push(row * 7 + col) } }
  const walkZ = () => { while (row !== targetRow) { row += Math.sign(targetRow - row); path.push(row * 7 + col) } }
  if (horizontalFirst) { walkX(); walkZ() } else { walkZ(); walkX() }
  person.route = pedestrianRoute(path, person.pose)
  person.previous = from
  person.node = target
  person.distance = 0
  person.speed = .58 + random(person) * .39
  person.trips++
}
export function createPedestrians(seed = 4271): PedestrianSimulation {
  const starts = [0, 3, 6, 8, 10, 12, 14, 17, 20, 22, 24, 27]
  const people = starts.map((node, index) => {
    const point = coordinates(node)
    const person: Pedestrian = { seed: (seed + Math.imul(index + 1, 7919)) >>> 0, node, previous: -1, route: createRoute([point]), distance: 0, speed: .7, rest: index % 4 * 1.3, trips: 0, pose: { x: point[0], z: point[1], yaw: 0, walking: 0, action: 'waiting' } }
    planNext(person)
    person.pose = { ...sampleRoute(person.route, 0), walking: 0, action: 'waiting' }
    return person
  })
  return { people, elapsed: 0, junctions: new Map(starts.map((node, index) => [node, index])) }
}

/** Small bounded increments keep pauses stable and prevent tab-resume jumps. */
export function advancePedestrians(simulation: PedestrianSimulation, elapsed: number) {
  const delta = Number.isFinite(elapsed) ? Math.max(0, Math.min(.05, elapsed)) : 0
  if (!delta) return simulation.people.map(person => person.pose)
  simulation.elapsed += delta
  // Only the person physically inside a crossing retains its reservation.
  // In particular, waiting for a distant destination never locks that node.
  for (const [node, owner] of simulation.junctions) {
    if (junctionAt(simulation.people[owner].pose) !== node) simulation.junctions.delete(node)
  }
  simulation.people.forEach((person, index) => {
    if (person.rest > 0) {
      person.rest = Math.max(0, person.rest - delta)
      person.pose.walking = 0
      person.pose.action = person.trips % 3 ? 'checking' : 'waiting'
      return
    }
    const stride = person.speed * (.94 + .06 * Math.sin(simulation.elapsed * .8 + index * 1.7))
    const nextDistance = Math.min(person.route.length, person.distance + stride * delta)
    const candidate = sampleRoute(person.route, nextDistance / person.route.length)
    const junction = junctionAt(candidate)
    const owner = simulation.junctions.get(junction)
    const crossingOccupied = junction >= 0 && owner !== undefined && owner !== index
    const occupied = simulation.people.some((other, otherIndex) => {
      if (otherIndex === index) return false
      return Math.hypot(other.pose.x - candidate.x, other.pose.z - candidate.z) < PEDESTRIAN_CLEARANCE
    })
    if (crossingOccupied || occupied) { person.pose.walking = 0; person.pose.action = 'waiting'; return }
    if (junction >= 0) simulation.junctions.set(junction, index)
    person.distance = nextDistance
    const edge = Math.min(person.distance, person.route.length - person.distance)
    person.pose = { ...candidate, walking: Math.min(1, .3 + edge * 1.5), action: 'walking' }
    if (person.distance >= person.route.length) {
      person.rest = random(person) < .28 ? .4 : 2 + random(person) * 7
      person.pose.walking = 0
      person.pose.action = 'checking'
      planNext(person)
    }
  })
  return simulation.people.map(person => person.pose)
}

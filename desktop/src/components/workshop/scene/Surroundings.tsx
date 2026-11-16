import { memo } from 'react'
import type { Position3 } from '../domain/types'
import { logisticsLayout } from '../data/layout'
import { Box, BoxBatch } from './IndustrialModels'
import IndustrialSign from './IndustrialSign'

const site = {
  base: '#3d4851',
  concrete: '#b7bfc3',
  sidewalk: '#d3d8da',
  joint: '#98a4ac',
  asphalt: '#626b73',
  shoulder: '#a4afb6',
  steel: '#596973',
  rail: '#a6b4bd',
  paint: '#eeeae1',
  yellow: '#ddba40',
  graphite: '#34444f',
}

/** Extents describe the illustrative site only; they never change data or camera bounds. */
export const industrialSite = {
  center: [-1, 0, 3.5] as Position3,
  size: [68, 51] as const,
  westFence: -33,
  eastFence: 31.2,
  backFence: -21.2,
  frontBoundary: 28.8,
  roadCenterZ: logisticsLayout.roadZ,
  roadClearWidth: 6.2,
}

function Bollard({ x, z }: { x: number; z: number }) {
  return <group position={[x, 0, z]}>
    <Box position={[0, .06, 0]} size={[.34, .12, .34]} color={site.graphite} />
    <Box position={[0, .54, 0]} size={[.17, .96, .17]} color={site.yellow} metalness={.3} roughness={.63} />
    {[.3, .68].map(y => <Box key={y} position={[0, y, 0]} size={[.179, .16, .179]} color={site.graphite} />)}
    <Box position={[0, 1.035, 0]} size={[.2, .05, .2]} color={site.yellow} />
  </group>
}

function FenceRun({ position, length, rotation = 0 }: { position: Position3; length: number; rotation?: number }) {
  const segments = Math.ceil(length / 3.6)
  const step = length / segments
  return <group position={position} rotation={[0, rotation, 0]}>
    <Box position={[0, .13, 0]} size={[length + .15, .26, .3]} color={site.concrete} roughness={.95} />
    {[.45, 1.65].map(y => <Box key={y} position={[0, y, 0]} size={[length, .055, .055]} color={site.steel} metalness={.45} />)}
    {Array.from({ length: segments + 1 }, (_, index) => <group key={index} position={[-length / 2 + index * step, 0, 0]}>
      <Box position={[0, .94, 0]} size={[.1, 1.88, .1]} color={site.steel} metalness={.5} />
      <Box position={[0, 1.9, 0]} size={[.14, .06, .14]} color={site.graphite} />
    </group>)}
    {Array.from({ length: segments * 5 }, (_, index) => <Box key={index} position={[-length / 2 + (index + .5) * length / (segments * 5), 1.04, 0]} size={[.024, 1.23, .024]} color={site.steel} metalness={.45} />)}
  </group>
}

function GuardRail({ x, z, length }: { x: number; z: number; length: number }) {
  const count = Math.ceil(length / 3)
  return <group position={[x, 0, z]}>
    <Box position={[0, .72, 0]} size={[length, .24, .09]} color={site.rail} metalness={.55} roughness={.6} />
    {[-.105, .105].map(y => <Box key={y} position={[0, .72 + y, -.035]} size={[length, .045, .07]} color="#c1cbd0" metalness={.5} />)}
    {Array.from({ length: count + 1 }, (_, index) => <group key={index} position={[-length / 2 + index * length / count, 0, .07]}>
      <Box position={[0, .39, 0]} size={[.09, .78, .1]} color={site.steel} metalness={.5} />
      <Box position={[0, .035, 0]} size={[.27, .07, .31]} color={site.graphite} />
    </group>)}
  </group>
}

function Crossing({ x }: { x: number }) {
  return <group>
    {Array.from({ length: 9 }, (_, index) => <Box key={index} position={[x, .062, logisticsLayout.roadZ - 2.7 + index * .675]} size={[1.85, .014, .32]} color={site.paint} roughness={.88} />)}
    {[-3.27, 3.27].map(offset => <Box key={offset} position={[x, .07, logisticsLayout.roadZ + offset]} size={[1.85, .016, .09]} color={site.yellow} />)}
  </group>
}

/** A bounded industrial yard replaces the unverified neighboring warehouses.
 * No kerb, fence, post or raised crossing enters the truck/forklift route. */
export const Surroundings = memo(function Surroundings() {
  return <group name="Pátio industrial em maquete — composição ilustrativa" userData={{ illustrative: true }}>
    <BoxBatch>
      {/* The dark plinth and concrete cap make a single compact, finite site. */}
      <Box position={[-1, -.5, 3.5]} size={[68, .82, 51]} color={site.base} roughness={.94} metalness={.03} />
      <Box position={[-1, -.09, 3.5]} size={[67.8, .1, 50.8]} color={site.concrete} roughness={.96} />
      <Box position={[0, -.5, logisticsLayout.roadZ]} size={[80, .82, 7.8]} color={site.base} roughness={.94} metalness={.03} />
      <Box position={[0, -.065, logisticsLayout.roadZ]} size={[80, .1, 7.8]} color={site.shoulder} roughness={.96} />

      {/* Broad loading apron stays clear through the four existing dock positions. */}
      <Box position={[0, -.005, 19.25]} size={[56, .09, 2.5]} color="#bdc5c9" roughness={.95} />
      {[-24, -16, -8, 0, 8, 16, 24].map(x => <Box key={x} position={[x, .046, 19.25]} size={[.025, .012, 2.4]} color={site.joint} />)}
      <Box position={[0, .043, 18.03]} size={[55.8, .012, .055]} color={site.joint} />
      <Box position={[0, .043, 20.45]} size={[55.8, .012, .07]} color={site.joint} />

      {/* The existing centerline route at Z23.5 remains open from X-37 to X37. */}
      <Box position={[0, .005, logisticsLayout.roadZ]} size={[80, .06, industrialSite.roadClearWidth]} color={site.asphalt} roughness={.98} metalness={.02} />
      {[-2.9, 2.9].map(offset => <Box key={offset} position={[0, .052, logisticsLayout.roadZ + offset]} size={[79.7, .014, .075]} color={site.paint} roughness={.9} />)}
      <Crossing x={-29.5} />
      <Crossing x={29.5} />

      {/* Side service walks and protected pedestrian frontage are outside vehicle sweeps. */}
      {[-30.5, 29.5].map(x => <group key={x}>
        <Box position={[x, .025, -.9]} size={[1.8, .13, 39.5]} color={site.sidewalk} roughness={.93} />
        {Array.from({ length: 13 }, (_, index) => <Box key={index} position={[x, .096, -19.2 + index * 3.05]} size={[1.77, .01, .022]} color={site.joint} />)}
        {[-.94, .94].map(offset => <Box key={offset} position={[x + offset, .075, -.9]} size={[.1, .23, 39.5]} color="#929fa8" roughness={.93} />)}
      </group>)}
      <Box position={[-.8, .065, 27.7]} size={[64.7, .19, 1.8]} color={site.sidewalk} roughness={.94} />
      {Array.from({ length: 22 }, (_, i) => <Box key={i} position={[-32 + i * 3, .165, 27.7]} size={[.022, .01, 1.77]} color={site.joint} />)}
      <Box position={[-.8, .07, 26.73]} size={[64.7, .24, .14]} color="#9eabb3" roughness={.9} />
      <Box position={[-.8, .06, 28.75]} size={[65.2, .28, .25]} color={site.graphite} roughness={.88} />

      {/* Drain channels sit flush with the pavement, never across a forklift bay. */}
      {[-30.5, 29.5].map(x => <group key={x}>
        <Box position={[x + (x < 0 ? 1.2 : -1.2), -.005, -.7]} size={[.2, .08, 38.8]} color={site.graphite} />
        {Array.from({ length: 32 }, (_, i) => <Box key={i} position={[x + (x < 0 ? 1.2 : -1.2), .042, -19.6 + i * 1.2]} size={[.22, .016, .08]} color="#7e8d98" />)}
      </group>)}

      <FenceRun position={[-.9, 0, industrialSite.backFence]} length={64.2} />
      <FenceRun position={[industrialSite.westFence, 0, -.9]} length={40} rotation={Math.PI / 2} />
      <FenceRun position={[industrialSite.eastFence, 0, -.9]} length={40} rotation={Math.PI / 2} />
      {/* Both lateral openings span Z19.1..27.2: no gate intersects the road. */}
      <FenceRun position={[industrialSite.westFence, 0, 28]} length={1.6} rotation={Math.PI / 2} />
      <FenceRun position={[industrialSite.eastFence, 0, 28]} length={1.6} rotation={Math.PI / 2} />
      <GuardRail x={-15.5} z={26.82} length={15} />
      <GuardRail x={15.5} z={26.82} length={15} />

      {[-27.1, 27.1].map(x => [18.7, 20.0].map(z => <Bollard key={x + ':' + z} x={x} z={z} />))}
      {[-32.5, 31.1].map(x => <group key={x}>
        <Box position={[x, 1.0, 19.5]} size={[.09, 2, .09]} color={site.steel} metalness={.45} />
        <Box position={[x, 1.75, 19.5]} size={[2.2, .7, .07]} color={site.graphite} />
      </group>)}
    </BoxBatch>
    <IndustrialSign text="RECEBIMENTO" position={[-20, .08, 19.45]} size={[5, .68]} rotation={[-Math.PI / 2, 0, 0]} color="#34444f" background="#bdc5c9" />
    <IndustrialSign text="EXPEDIÇÃO" position={[20, .08, 19.45]} size={[4.6, .68]} rotation={[-Math.PI / 2, 0, 0]} color="#34444f" background="#bdc5c9" />
    <IndustrialSign text="PEDESTRES" position={[-15.5, .18, 27.65]} size={[4.3, .56]} rotation={[-Math.PI / 2, 0, 0]} color="#34444f" background={site.sidewalk} />
    <IndustrialSign text="PEDESTRES" position={[15.5, .18, 27.65]} size={[4.3, .56]} rotation={[-Math.PI / 2, 0, 0]} color="#34444f" background={site.sidewalk} />
    <IndustrialSign text="ACESSO LOGÍSTICO" position={[-32.5, 1.75, 19.55]} size={[2.1, .6]} color="#f1f2ef" background={site.graphite} />
    <IndustrialSign text="SAÍDA / ACESSO" position={[31.1, 1.75, 19.55]} size={[2.1, .6]} color="#f1f2ef" background={site.graphite} />
  </group>
})

export default Surroundings

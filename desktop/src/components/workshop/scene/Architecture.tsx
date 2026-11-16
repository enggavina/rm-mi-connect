import { memo } from 'react'
import type { Position3, SceneLayers } from '../domain/types'
import { logisticsLayout, productionCells, workshopBounds } from '../data/layout'
import { Box, BoxBatch, MachineTool } from './IndustrialModels'
import Crane from './Crane'
import TestRoom from './TestRoom'
import BrandDecal from './BrandDecal'
import IndustrialSign from './IndustrialSign'
import Roof from './Roof'

const building = {
  concrete: '#aeb5b7',
  floor: '#d2d6d5',
  joint: '#b2b9bb',
  walkway: '#a7b1b6',
  line: '#e2b936',
  paint: '#f0eee5',
  steel: '#3e4b54',
  steelEdge: '#697780',
  cladding: '#9e3540',
  claddingRib: '#b64951',
  gate: '#b92332',
  base: '#818c93',
  glass: '#95aab5',
}
const columnZ = [-16.8, -8.4, 0, 8.4, 16.8]
const pedestrianX = [-26.4, -17.6, -8.8, 0, 8.8, 17.6, 26.4]

function Beam({ from, to, width = .1, color = building.steel }: { from: Position3; to: Position3; width?: number; color?: string }) {
  const dx = to[0] - from[0], dy = to[1] - from[1]
  return <Box
    position={[(from[0] + to[0]) / 2, (from[1] + to[1]) / 2, (from[2] + to[2]) / 2]}
    size={[Math.hypot(dx, dy), width, width]}
    rotation={[0, 0, Math.atan2(dy, dx)]}
    color={color}
    metalness={.45}
    roughness={.58}
  />
}

/** I-section columns end at the roof eaves; their footing stays outside the aisle. */
function SteelColumn({ x, z }: { x: number; z: number }) {
  return <group position={[x, 0, z]}>
    <Box position={[0, .18, 0]} size={[.56, .36, .65]} color={building.concrete} roughness={.94} />
    <Box position={[0, .39, 0]} size={[.5, .09, .57]} color={building.steelEdge} metalness={.55} />
    <Box position={[0, 4.83, 0]} size={[.12, 8.82, .38]} color={building.steel} metalness={.5} />
    {[-.22, .22].map(offset => <Box key={offset} position={[0, 4.83, offset]} size={[.4, 8.82, .07]} color={building.steel} metalness={.5} />)}
    <Box position={[0, 9.27, 0]} size={[.54, .12, .62]} color={building.steelEdge} metalness={.5} />
    {[-.17, .17].map(a => [-.2, .2].map(b => <Box key={a + ':' + b} position={[a, .46, b]} size={[.065, .07, .065]} color="#b2bcc1" metalness={.65} />))}
  </group>
}

function Office({ x, z }: { x: number; z: number }) {
  return <group position={[x, 0, z]}>
    <Box position={[0, 1.02, -.2]} size={[2.2, .12, 1.05]} color="#bac2c5" roughness={.8} />
    {[-.93, .93].map(offset => <Box key={offset} position={[offset, .53, -.2]} size={[.08, .96, .82]} color={building.steel} />)}
    <Box position={[0, 1.42, -.4]} size={[.82, .55, .09]} color="#293b47" />
    <Box position={[0, 1.42, -.34]} size={[.72, .43, .018]} color="#8fa4b0" />
    <Box position={[0, 1.14, -.4]} size={[.09, .23, .09]} color={building.steel} />
    <Box position={[0, 1.11, .14]} size={[.7, .035, .28]} color="#6e7b83" />
    <Box position={[0, .58, 1.05]} size={[.7, .14, .7]} color="#475c69" />
    <Box position={[0, 1, 1.36]} size={[.7, .85, .13]} color="#475c69" />
    <Box position={[0, .28, 1.05]} size={[.12, .5, .12]} color="#89969f" />
    <Box position={[-2.8, .72, -.7]} size={[.72, 1.45, .9]} color="#b4bdc3" />
    <Box position={[0, .56, -1.95]} size={[6.7, 1.12, .09]} color="#c8ced1" roughness={.9} />
    <Box position={[-3.36, .56, -.55]} size={[.09, 1.12, 2.7]} color="#c8ced1" roughness={.9} />
    <Box position={[0, 1.14, -1.95]} size={[6.7, .06, .12]} color="#647581" />
  </group>
}

function Rack({ x, z }: { x: number; z: number }) {
  return <group position={[x, 0, z]}>
    {[-1.2, 1.2].map(a => [-.45, .45].map(b => <Box key={a + ':' + b} position={[a, 1.35, b]} size={[.08, 2.7, .08]} color="#a33943" />))}
    {[.25, 1.35, 2.45].map(y => <Box key={y} position={[0, y, 0]} size={[2.5, .1, 1.05]} color="#829099" />)}
    <Box position={[-.45, .46, 0]} size={[1.3, .28, .8]} color="#b6bfc3" />
  </group>
}

const WorkshopFloor = memo(function WorkshopFloor() {
  const { width, depth } = workshopBounds
  return <BoxBatch>
    <Box position={[0, -.31, 0]} size={[width, .6, depth]} color={building.concrete} roughness={.96} />
    <Box position={[0, .005, 0]} size={[width - .15, .05, depth - .15]} color={building.floor} roughness={.95} />
    {[-24, -16, -8, 0, 8, 16, 24].map(x => <Box key={x} position={[x, .036, 0]} size={[.018, .008, depth - .2]} color={building.joint} />)}
    {[-14, -7, 0, 7, 14].map(z => <Box key={z} position={[0, .036, z]} size={[width - .2, .008, .018]} color={building.joint} />)}

    {/* Paint follows the existing pedestrian network; cell coordinates do not move. */}
    {pedestrianX.map(x => {
      const outer = Math.abs(x) > 26
      const edge = outer ? .68 : .98
      return <group key={x}>
        <Box position={[x, .045, .6]} size={[outer ? 1.3 : 1.75, .012, 24]} color={building.walkway} roughness={.94} />
        {[-edge, edge].map(offset => <Box key={offset} position={[x + offset, .062, .6]} size={[.05, .013, 24]} color={building.line} roughness={.85} />)}
      </group>
    })}
    {logisticsLayout.crossAislesZ.map(z => <group key={z}>
      <Box position={[0, .065, z]} size={[53.5, .012, 1.8]} color={building.walkway} roughness={.94} />
      {[-.94, .94].map(offset => <Box key={offset} position={[0, .08, z + offset]} size={[53.5, .012, .045]} color={building.line} />)}
    </group>)}
    {[-8.8, -4.9, 1.2, 8, 11].map(z => <group key={z} position={[0, .09, z]}>
      <Box size={[.09, .014, .7]} color={building.paint} />
      {[-1, 1].map(side => <Box key={side} position={[side * .15, 0, -.27]} size={[.07, .014, .4]} rotation={[0, side * .8, 0]} color={building.paint} />)}
    </group>)}
    {[-20, -7, 7, 20].map(x => <group key={x}>
      <Box position={[x, .045, 17.5]} size={[10.4, .025, .12]} color={building.steel} />
      {Array.from({ length: 10 }, (_, i) => <Box key={i} position={[x - 4.5 + i, .072, 17.65]} size={[.47, .016, .7]} rotation={[0, -.55, 0]} color={i % 2 ? '#46525b' : building.line} />)}
    </group>)}
    <Box position={[0, -.015, 17.98]} size={[56, .12, .12]} color="#8d989e" roughness={.8} />
  </BoxBatch>
})

/** The envelope is intentionally cut away at the front and sides. */
const WorkshopEnvelope = memo(function WorkshopEnvelope() {
  return <group name="Galpão MI em corte — arquitetura conceitual">
    <BoxBatch>
      <Box position={[0, 4.65, -17.96]} size={[56, 9.3, .22]} color={building.cladding} roughness={.76} metalness={.25} />
      <Box position={[0, .25, -17.77]} size={[55.7, .5, .16]} color={building.base} roughness={.95} />
      {/* Ribbed red cladding and high, opaque clerestory glazing read as one facade. */}
      {Array.from({ length: 55 }, (_, i) => <Box key={i} position={[-27 + i, 4.87, -17.79]} size={[.06, 8.75, .075]} color={building.claddingRib} roughness={.73} metalness={.3} />)}
      {[-24, -18, -12, -6, 0, 6, 12, 18, 24].map(x => <group key={x}>
        <Box position={[x, 7.18, -17.7]} size={[5.65, 1.12, .11]} color={building.steel} />
        <Box position={[x, 7.18, -17.62]} size={[5.4, .87, .04]} color={building.glass} roughness={.38} metalness={.2} />
        <Box position={[x, 7.18, -17.58]} size={[.065, .92, .04]} color="#627582" />
        <Box position={[x, 7.18, -17.58]} size={[5.4, .045, .04]} color="#627582" />
      </group>)}
      <Box position={[0, 9.27, -17.76]} size={[56.2, .18, .45]} color={building.steel} metalness={.45} />

      {/* Existing red gate and original artwork remain the identity anchor. */}
      <Box position={[0, 2.05, -17.7]} size={[6.5, 4.1, .13]} color={building.gate} roughness={.7} metalness={.32} />
      {[-3.4, 3.4].map(x => <Box key={x} position={[x, 2.18, -17.62]} size={[.22, 4.36, .24]} color={building.steel} />)}
      <Box position={[0, 4.32, -17.62]} size={[7.02, .24, .24]} color={building.steel} />
      {Array.from({ length: 9 }, (_, i) => <Box key={i} position={[-2.9 + i * .72, 2.05, -17.61]} size={[.045, 3.9, .035]} color="#d15a60" />)}
      <Beam from={[-3.1, .2, -17.57]} to={[0, 3.9, -17.57]} width={.075} color="#d15a60" />
      <Beam from={[0, 3.9, -17.57]} to={[3.1, .2, -17.57]} width={.075} color="#d15a60" />

      {[-27.9, 27.9].map(x => <group key={x}>
        <Box position={[x, .32, 0]} size={[.22, .64, 35.6]} color="#aeb6ba" roughness={.96} />
        <Box position={[x, .66, 0]} size={[.25, .075, 35.6]} color={building.steelEdge} />
      </group>)}
      {[-27.4, 27.4].map(x => columnZ.map(z => <SteelColumn key={x + ':' + z} x={x} z={z} />))}
      {[-27.4, 27.4].map(x => <Box key={x} position={[x, 9.13, 0]} size={[.22, .28, 35.8]} color={building.steel} metalness={.5} />)}
      {productionCells.filter(item => item.kind === 'support').map(item => <Office key={item.id} x={item.position[0]} z={item.position[2]} />)}
    </BoxBatch>
    <BrandDecal position={[0, 2.05, -17.48]} width={2.8} />
    <IndustrialSign text="OFICINA DE EQUIPAMENTOS" position={[12.1, 5.47, -17.57]} size={[15, .8]} color="#f3f4f2" background={building.cladding} />
    <IndustrialSign text="APOIO TÉCNICO" position={[-16, 5.47, -17.57]} size={[12, .8]} color="#f3f4f2" background={building.cladding} />
  </group>
})

const WorkshopFixtures = memo(function WorkshopFixtures() {
  return <BoxBatch>
    <MachineTool position={[24, 0, -5.8]} rotation={0} />
    <Box position={[-15.9, .85, 1]} size={[.85, 1.7, 1.1]} color="#3271a1" />
    <Box position={[-15.9, 1.13, 1.57]} size={[.65, .45, .04]} color="#cbd3d8" />
    <group position={[22, 0, 6.02]}>
      <Box position={[0, 1.2, 0]} size={[6.2, 2.4, .1]} color="#aebcc3" />
      <Box position={[0, 1.25, .07]} size={[2.2, 1.3, .03]} color="#7f98a7" roughness={.42} metalness={.2} />
      <Box position={[3, 1.2, 1.3]} size={[.1, 2.4, 2.6]} color="#aebcc3" />
      <Box position={[0, 2.42, 0]} size={[6.3, .12, .15]} color={building.steel} />
    </group>
    <Rack x={-10.4} z={13.55} />
    <Rack x={3.5} z={13.55} />
    <Box position={[24, .7, 13.7]} size={[1.2, 1.4, .65]} color="#9aa9b3" />
  </BoxBatch>
})

export const Architecture = memo(function Architecture({ layers, animationRunning = false, testRoomOccupied = false }: { layers: SceneLayers; animationRunning?: boolean; testRoomOccupied?: boolean }) {
  return <group>
    <WorkshopFloor />
    {layers.architecture && <WorkshopEnvelope />}
    <Roof mode={layers.roofMode ?? (layers.roof ? 'translucent' : 'hidden')} />
    <WorkshopFixtures />
    {layers.cranes && <Crane animationRunning={animationRunning} />}
    <TestRoom showIllustrativeMotor={!testRoomOccupied} />
    <IndustrialSign text="SALA DE TESTES" position={[13.3, 2.28, 5.82]} size={[4.3, .48]} color="#26333c" background="#f0f2f2" />
  </group>
})

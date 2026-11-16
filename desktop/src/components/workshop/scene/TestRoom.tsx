import { memo, useMemo } from 'react'
import { CatmullRomCurve3, Vector3 } from 'three'
import type { Position3 } from '../domain/types'
import { Box, BoxBatch, MotorModel } from './IndustrialModels'

export const testRoomOperators = [
  { position: [11.3, .2, 7.05] as Position3, rotation: Math.PI, pose: 'panel' },
  { position: [13, .2, 8.65] as Position3, rotation: Math.PI / 2, pose: 'inspect' },
  { position: [15.7, .2, 10.05] as Position3, rotation: -Math.PI / 2, pose: 'checklist' },
] as const

function Cable({ points, color = '#283b49', radius = .035 }: { points: Position3[]; color?: string; radius?: number }) {
  const curve = useMemo(() => new CatmullRomCurve3(points.map(point => new Vector3(...point))), [points])
  return <mesh><tubeGeometry args={[curve, 30, radius, 6, false]} /><meshStandardMaterial color={color} roughness={.8} /></mesh>
}

/** Cutaway test room inside the conceptual Testes Finais cell. Equipment and
 * displays are scenic, without invented readings or operational identifiers. */
export default memo(function TestRoom({ showIllustrativeMotor = true }: { showIllustrativeMotor?: boolean }) {
  return <group name="Sala de testes ilustrativa — equipamentos e instrumentos cenográficos">
    <BoxBatch>
      <Box position={[13.2, .12, 8.3]} size={[6.6, .15, 5.2]} color="#bdc9cc" />
      <Box position={[11.45, .59, 8.85]} size={[2.75, .14, 2.65]} color="#718b9c" />
      {[[10.35, 7.85], [12.55, 7.85], [10.35, 9.85], [12.55, 9.85]].map(([x, z]) => <Box key={`${x}-${z}`} position={[x, .4, z]} size={[.1, .4, .1]} color="#30465a" />)}
      <Box position={[13.2, 1.37, 5.73]} size={[6.6, 2.4, .13]} color="#dce3e4" />
      <Box position={[16.43, .67, 8.3]} size={[.13, 1.1, 5.2]} color="#d4dfe2" />
      <Box position={[13.2, 2.63, 5.73]} size={[6.6, .15, .2]} color="#176bb0" />
      <Box position={[16.43, 1.27, 8.3]} size={[.17, .1, 5.2]} color="#176bb0" />
      <Box position={[10.02, 1.2, 6.5]} size={[.17, 2.1, 1.6]} color="#176bb0" />
      <Box position={[14.7, .38, 7.8]} size={[2.05, .4, 3.7]} color="#607885" />
      {[-.66, .66].map(x => <Box key={x} position={[14.7 + x, .65, 7.8]} size={[.17, .16, 3.45]} color="#344e60" />)}
      {[6.8, 8.7].map(z => <Box key={z} position={[14.7, .75, z]} size={[1.8, .25, .3]} color="#c99531" />)}
      <Box position={[11.25, 1.1, 6.3]} size={[1.8, 1.8, .7]} color="#d3e0e4" />
      <Box position={[11.25, 1.33, 6.68]} size={[1.55, 1.13, .07]} color="#263e52" />
      <Box position={[10.92, 1.58, 6.73]} size={[.62, .35, .035]} color="#4f8bba" />
      <Box position={[11.63, 1.58, 6.73]} size={[.45, .35, .035]} color="#9bc1d4" />
      <Box position={[11.25, .87, 6.73]} size={[1.25, .08, .035]} color="#0e1724" />
      <Box position={[12.4, .5, 6.22]} size={[.32, .65, .5]} color="#cf4049" />
      <Box position={[15.65, .77, 9.65]} size={[.85, .08, .5]} color="#c2d0d5" rotation={[-.12, 0, 0]} />
      <Box position={[15.65, .43, 9.65]} size={[.07, .65, .07]} color="#5a7381" />
      <Box position={[15.65, .83, 9.65]} size={[.53, .035, .33]} color="#f4f7f8" rotation={[-.12, 0, 0]} />
      {[-.35, 1.8].map(offset => <Box key={offset} position={[13.2 + offset, .67, 10.35]} size={[.09, 1, .09]} color="#d9aa30" />)}
      <Box position={[13.93, 1.15, 10.35]} size={[2.17, .08, .08]} color="#d9aa30" />
      <Box position={[13.93, .65, 10.35]} size={[2.17, .05, .06]} color="#d9aa30" />
    </BoxBatch>
    {showIllustrativeMotor && <group position={[14.7, 1.45, 7.8]} rotation={[0, Math.PI / 2, 0]}><MotorModel kind="motor" color="#176bb0" size={.85} /></group>}
    {[-.35, 0, .35].map((offset, i) => <mesh key={offset} position={[11.25 + offset, 1.13, 6.76]} rotation={[Math.PI / 2, 0, 0]}><cylinderGeometry args={[.065, .065, .05, 12]} /><meshStandardMaterial color={i === 0 ? '#df3445' : i === 1 ? '#e7b63b' : '#3d9a82'} roughness={.5} /></mesh>)}
    <Cable points={[[11.95, .8, 6.4], [12.5, .28, 6.55], [13.3, .23, 6.9], [14.1, .32, 7.2], [14.1, 1.9, 7.7]]} />
    <Cable points={[[11.95, .65, 6.35], [12.7, .24, 6.4], [13.6, .23, 6.65], [15.1, .4, 6.7], [15.1, 1.55, 7.5]]} color="#bd573d" radius={.026} />
    <mesh position={[10.95, 1.58, 6.76]}><planeGeometry args={[.48, .19]} /><meshBasicMaterial color="#9cd1e2" /></mesh>
  </group>
})

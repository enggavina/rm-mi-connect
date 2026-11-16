import { createContext, memo, useContext, useLayoutEffect, useRef } from 'react'
import type { ReactNode } from 'react'
import { BoxGeometry, CylinderGeometry, Group, InstancedMesh, Matrix4, MeshStandardMaterial, Quaternion, Vector3, Euler } from 'three'
import type { Position3, ModelKind } from '../domain/types'

export const colors = { yellow: '#e6b820', yellowLight: '#f1c945', steel: '#53686c', darkSteel: '#25394c', blue: '#176bb0', red: '#e73e42', floor: '#c7c9be', silver: '#b0bcb8', copper: '#ad744d', wall: '#e6e0d0' }

interface BoxProps { position?: Position3; size: Position3; color?: string; rotation?: Position3; metalness?: number; roughness?: number; opacity?: number }
const unitBox = new BoxGeometry(1, 1, 1)
const materialCache = new Map<string, MeshStandardMaterial>()
const cylinderCache = new Map<number, CylinderGeometry>()
const BatchContext = createContext(false)

function industrialMaterial(color: string, metalness = .12, roughness = .68, opacity = 1) {
  const key = [color, metalness, roughness, opacity].join('|')
  let material = materialCache.get(key)
  if (!material) {
    material = new MeshStandardMaterial({ color, metalness, roughness, opacity, transparent: opacity < 1 })
    materialCache.set(key, material)
  }
  return material
}

/** Static architecture boxes are combined by material into instanced draws.
 * Interactive equipment stays outside this batch, preserving object selection. */
export function BoxBatch({ children }: { children: ReactNode }) {
  const group = useRef<Group>(null)
  useLayoutEffect(() => {
    if (!group.current) return
    const root = group.current
    root.updateWorldMatrix(true, true)
    const inverse = root.matrixWorld.clone().invert()
    const byMaterial = new Map<MeshStandardMaterial, Matrix4[]>()
    root.traverse(node => {
      const material = node.userData.boxMaterial as MeshStandardMaterial | undefined
      if (!material) return
      const matrices = byMaterial.get(material) ?? []
      matrices.push(new Matrix4().multiplyMatrices(inverse, node.matrixWorld))
      byMaterial.set(material, matrices)
    })
    const batches = [...byMaterial].map(([material, matrices]) => {
      const mesh = new InstancedMesh(unitBox, material, matrices.length)
      matrices.forEach((matrix, index) => mesh.setMatrixAt(index, matrix))
      mesh.instanceMatrix.needsUpdate = true
      mesh.castShadow = material.opacity === 1
      mesh.receiveShadow = true
      mesh.computeBoundingSphere()
      root.add(mesh)
      return mesh
    })
    return () => { batches.forEach(mesh => { root.remove(mesh); mesh.dispose() }) }
  }, [children])
  return <BatchContext.Provider value><group ref={group} dispose={null}>{children}</group></BatchContext.Provider>
}

export function Box({ position, size, color = colors.steel, rotation, metalness = .12, roughness = .68, opacity = 1 }: BoxProps) {
  const batched = useContext(BatchContext)
  const material = industrialMaterial(color, metalness, roughness, opacity)
  if (batched) return <group position={position} rotation={rotation} scale={size} userData={{ boxMaterial: material }} />
  return <mesh position={position} rotation={rotation} scale={size} geometry={unitBox} material={material} castShadow={opacity === 1} receiveShadow dispose={null} />
}

function Cylinder({ position, radius, length, color, axis = 'x', segments = 24 }: { position: Position3; radius: number; length: number; color: string; axis?: 'x' | 'y' | 'z'; segments?: number }) {
  if (!cylinderCache.has(segments)) cylinderCache.set(segments, new CylinderGeometry(1, 1, 1, segments))
  return <mesh position={position} scale={[radius, length, radius]} rotation={axis === 'x' ? [0, 0, Math.PI / 2] : axis === 'z' ? [Math.PI / 2, 0, 0] : [0, 0, 0]} geometry={cylinderCache.get(segments)} material={industrialMaterial(color, .4, .5)} castShadow receiveShadow dispose={null} />
}

function Rings({ count, start, step, radius, tube, color }: { count: number; start: number; step: number; radius: number; tube: number; color: string }) {
  const ref = useRef<InstancedMesh>(null)
  useLayoutEffect(() => {
    const matrix = new Matrix4()
    const rotation = new Quaternion().setFromEuler(new Euler(0, Math.PI / 2, 0))
    for (let i = 0; i < count; i++) ref.current?.setMatrixAt(i, matrix.compose(new Vector3(start + i * step, 0, 0), rotation, new Vector3(1, 1, 1)))
    if (ref.current) ref.current.instanceMatrix.needsUpdate = true
  }, [count, start, step])
  return <instancedMesh ref={ref} args={[undefined, undefined, count]} castShadow receiveShadow><torusGeometry args={[radius, tube, 4, 24]} /><meshStandardMaterial color={color} roughness={.55} metalness={.3} /></instancedMesh>
}

function Bolts({ x, radius }: { x: number; radius: number }) {
  const ref = useRef<InstancedMesh>(null)
  useLayoutEffect(() => {
    const matrix = new Matrix4()
    const rotation = new Quaternion().setFromEuler(new Euler(0, 0, Math.PI / 2))
    for (let i = 0; i < 6; i++) {
      const a = i * Math.PI / 3
      ref.current?.setMatrixAt(i, matrix.compose(new Vector3(x, Math.sin(a) * radius, Math.cos(a) * radius), rotation, new Vector3(1, 1, 1)))
    }
    if (ref.current) ref.current.instanceMatrix.needsUpdate = true
  }, [x, radius])
  return <instancedMesh ref={ref} args={[undefined, undefined, 6]} castShadow><cylinderGeometry args={[.045, .045, .05, 6]} /><meshStandardMaterial color="#c3c9c4" metalness={.4} roughness={.5} /></instancedMesh>
}

export function MotorModel({ kind = 'motor', color = colors.blue, size = 1 }: { kind?: ModelKind; color?: string; size?: number }) {
  if (kind === 'generator') return <group scale={size} name="Gerador industrial estilizado">
    <Box position={[0, -.82, 0]} size={[3.45, .22, 1.75]} color="#25394c" />
    <Cylinder position={[0, 0, 0]} radius={.75} length={2.05} color={color} />
    <Rings count={9} start={-.9} step={.225} radius={.77} tube={.035} color={color} />
    <Cylinder position={[1.15, 0, 0]} radius={.77} length={.24} color={color} />
    <Cylinder position={[-1.18, 0, 0]} radius={.72} length={.33} color="#12518b" />
    <Cylinder position={[1.34, 0, 0]} radius={.38} length={.15} color="#9caeb9" />
    <Cylinder position={[1.61, 0, 0]} radius={.19} length={.56} color="#c8d3db" />
    <Bolts x={1.29} radius={.58} />
    <Box position={[0, .89, 0]} size={[1.9, .48, 1.18]} color={color} />
    <Box position={[0, 1.16, 0]} size={[2.04, .07, 1.29]} color="#3287cb" />
    {Array.from({ length: 9 }, (_, i) => <Box key={i} position={[-.76 + i * .19, .9, .6]} size={[.07, .31, .02]} color="#143956" />)}
    <Box position={[-.5, .22, .84]} size={[.71, .7, .27]} color={color} />
    <Box position={[-.5, .23, .99]} size={[.34, .19, .025]} color="#d8e1e7" />
    {[-.72, .72].map(x => <Box key={x} position={[x, -.65, 0]} size={[.38, .35, 1.61]} color={color} />)}
  </group>
  if (kind === 'transformer') return <group scale={size} name="Transformador industrial estilizado">
    <Box position={[0, -.64, 0]} size={[2.35, .18, 1.64]} color="#36485a" />
    <Box position={[0, .13, 0]} size={[1.88, 1.45, 1.28]} color={color} />
    <Box position={[0, .89, 0]} size={[2.1, .12, 1.52]} color="#3985bd" />
    {[-1, 1].map(side => Array.from({ length: 7 }, (_, i) => <Box key={`${side}-${i}`} position={[-.76 + i * .25, .06, side * .78]} size={[.09, 1.16, .34]} color={color} />))}
    {[-.62, 0, .62].map(x => <group key={x}>
      <Cylinder position={[x, 1.13, 0]} radius={.11} length={.42} color="#a47b56" axis="y" />
      {[1, 1.11, 1.22].map(y => <Cylinder key={y} position={[x, y, 0]} radius={.17} length={.045} color="#855d3f" axis="y" segments={12} />)}
      <Cylinder position={[x, 1.39, 0]} radius={.065} length={.15} color="#c4cbd0" axis="y" />
    </group>)}
    <Box position={[0, .27, .66]} size={[.56, .31, .025]} color="#cdd5da" />
  </group>
  if (kind === 'drive') return <group scale={size} name="Drive industrial estilizado">
    <Box position={[0, .15, 0]} size={[1.6, 1.9, 1]} color="#bdc8d1" />
    <Box position={[0, .18, .52]} size={[1.42, 1.72, .06]} color="#e0e7eb" />
    <Box position={[0, .57, .56]} size={[.86, .55, .045]} color="#0e1724" />
    <Box position={[-.08, .65, .59]} size={[.58, .23, .02]} color="#73b2c9" />
    {[-.22, 0, .22].map(x => <Box key={x} position={[x, .4, .6]} size={[.1, .07, .02]} color={x === .22 ? '#e73e42' : '#4b6980'} />)}
    {Array.from({ length: 6 }, (_, i) => <Box key={i} position={[0, -.17 - i * .08, .56]} size={[.92, .026, .02]} color="#6b7f90" />)}
    <Box position={[0, -.88, 0]} size={[1.74, .15, 1.12]} color="#24364c" />
  </group>
  if (kind === 'rotor' || kind === 'shaft') return <group scale={size}>
    <Cylinder position={[0, 0, 0]} radius={kind === 'shaft' ? .15 : .16} length={3.25} color="#b5bdb7" />
    <Cylinder position={[-1.15, 0, 0]} radius={.22} length={.25} color="#798a8b" />
    <Cylinder position={[1.15, 0, 0]} radius={.22} length={.25} color="#798a8b" />
    {kind === 'rotor' && <><Cylinder position={[0, 0, 0]} radius={.54} length={1.5} color="#bbb296" /><Rings count={13} start={-.7} step={.115} radius={.54} tube={.025} color="#8c927d" /><Cylinder position={[-.83, 0, 0]} radius={.58} length={.14} color={colors.copper} /><Cylinder position={[.83, 0, 0]} radius={.58} length={.14} color={colors.copper} /><Bolts x={.91} radius={.38} /></>}
  </group>

  if (kind === 'stator' || kind === 'housing') return <group scale={size}>
    <Rings count={9} start={-.7} step={.175} radius={.6} tube={.14} color={color} />
    <Rings count={2} start={-.8} step={1.6} radius={.65} tube={.12} color={color} />
    {kind === 'stator' && <Rings count={2} start={-.83} step={1.66} radius={.46} tube={.07} color={colors.copper} />}
    {kind === 'stator' && Array.from({ length: 16 }, (_, i) => {
      const a = i * Math.PI / 8
      return <Box key={i} position={[0, Math.sin(a) * .45, Math.cos(a) * .45]} size={[1.5, .055, .06]} color="#bc8d58" rotation={[a, 0, 0]} metalness={.5} />
    })}
    {[-.5, .5].map(x => <Box key={x} position={[x, -.64, 0]} size={[.28, .22, 1.35]} color={color} />)}
    <Bolts x={.93} radius={.64} />
  </group>

  return <group scale={size}>
    <Cylinder position={[0, 0, 0]} radius={.55} length={1.65} color={color} />
    <Rings count={11} start={-.65} step={.13} radius={.58} tube={.04} color={color} />
    <Cylinder position={[.91, 0, 0]} radius={.59} length={.19} color={color} />
    <Cylinder position={[1.03, 0, 0]} radius={.3} length={.09} color="#7e9393" />
    <Cylinder position={[1.35, 0, 0]} radius={.14} length={.65} color="#c4ceca" />
    <Box position={[1.38, .145, 0]} size={[.3, .035, .08]} color="#657879" />
    <Cylinder position={[-1, 0, 0]} radius={.55} length={.3} color={colors.darkSteel} />
    <Rings count={4} start={-1.12} step={.075} radius={.56} tube={.025} color="#859491" />
    <Bolts x={1.025} radius={.45} />
    <Box position={[0, .65, 0]} size={[.65, .25, .55]} color={color} />
    <Box position={[0, .8, 0]} size={[.72, .07, .6]} color="#7c9190" />
    <Cylinder position={[.42, .66, 0]} radius={.07} length={.18} color="#39494b" />
    {[-.52, .52].map(x => <Box key={x} position={[x, -.55, 0]} size={[.3, .25, 1.3]} color={color} />)}
    <Box position={[-.25, .1, .576]} size={[.4, .2, .015]} color="#d3d6ca" />
  </group>
}

export const Bench = memo(function Bench({ kind }: { kind: 'bench' | 'support' | 'test' }) {
  if (kind === 'support') return <BoxBatch>
    <Box position={[0, .12, 0]} size={[3.4, .22, 1.9]} color="#536266" />
    {[-1.15, 1.15].map(x => <group key={x} position={[x, 0, 0]}>
      <Box position={[0, .4, 0]} size={[.28, .65, 1.75]} color={colors.yellow} />
      <Box position={[0, .8, -.38]} size={[.32, .6, .23]} rotation={[.65, 0, 0]} color={colors.yellow} />
      <Box position={[0, .8, .38]} size={[.32, .6, .23]} rotation={[-.65, 0, 0]} color={colors.yellow} />
    </group>)}
  </BoxBatch>
  if (kind === 'test') return <BoxBatch>
    <Box position={[0, .15, 0]} size={[3.4, .28, 2.15]} color="#5f737d" />
    {[-.7, .7].map(z => <Box key={z} position={[0, .38, z]} size={[3.15, .25, .16]} color="#3c4b52" />)}
    {[-1.05, 1.05].map(x => <Box key={x} position={[x, .6, 0]} size={[.3, .4, 1.7]} color={colors.yellow} />)}
    <Box position={[-2, .65, -.65]} size={[.5, 1.25, .7]} color="#e3e1d5" />
    <Box position={[-1.74, .9, -.65]} size={[.02, .4, .48]} color="#3e555c" />
    <Box position={[-1.72, .51, -.45]} size={[.03, .08, .08]} color="#d95b49" />
  </BoxBatch>
  return <BoxBatch>
    <Box position={[0, 1.02, 0]} size={[3.1, .17, 1.8]} color="#a6a497" />
    <Box position={[0, .91, 0]} size={[3.05, .12, 1.75]} color={colors.red} />
    {[-1.35, 1.35].map(x => [-.69, .69].map(z => <Box key={`${x}-${z}`} position={[x, .47, z]} size={[.11, .9, .11]} color={colors.red} />))}
    {[-.7, .7].map(z => <Box key={z} position={[0, .22, z]} size={[2.8, .1, .1]} color={colors.red} />)}
    <Box position={[0, .27, 0]} size={[2.76, .07, 1.4]} color="#835b50" />
    <Box position={[-.7, .43, 0]} size={[.7, .25, .65]} color="#52666d" />
    <Box position={[.55, .4, .15]} size={[.6, .2, .5]} color="#b0aa92" />
  </BoxBatch>
})

export function MachineTool({ position, rotation = 0 }: { position: Position3; rotation?: number }) {
  return <group position={position} rotation={[0, rotation, 0]}>
    <Box position={[0, .18, 0]} size={[2.4, .35, 1.65]} color="#3f535b" />
    <Box position={[-.7, 1.35, -.25]} size={[.8, 2.4, 1.1]} color={colors.blue} />
    <Box position={[-.55, 2.6, 0]} size={[1.1, .75, 1.5]} color="#47769a" />
    <Box position={[.1, 1.04, .3]} size={[2.6, .3, 1.3]} color="#6d8185" />
    {[-.25, .05, .35, .65].map(z => <Box key={z} position={[.1, 1.2, z]} size={[2.5, .025, .025]} color="#3a5056" />)}
    <Cylinder position={[-.3, 1.96, .46]} radius={.1} length={.55} color="#b7c3be" axis="y" />
    <Box position={[.3, .6, .2]} size={[.7, .65, .95]} color={colors.blue} />
    <mesh position={[.35, .8, .77]}><torusGeometry args={[.25, .025, 6, 18]} /><meshStandardMaterial color="#c5cec7" metalness={.6} roughness={.3} /></mesh>
    <Box position={[.35, .8, .77]} size={[.03, .48, .03]} color="#c5cec7" />
    <Box position={[.35, .8, .77]} size={[.48, .03, .03]} color="#c5cec7" />
    <Box position={[-.12, 2.6, .3]} size={[.03, .35, .4]} color="#d9decc" />
    <Box position={[-.1, 2.64, .3]} size={[.025, .13, .22]} color="#2c474d" />
  </group>
}

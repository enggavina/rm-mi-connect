import { memo, useEffect, useLayoutEffect, useMemo, useRef } from 'react'
import { useFrame, useThree } from '@react-three/fiber'
import { BoxGeometry, Euler, Group, InstancedMesh, Matrix4, MeshStandardMaterial, Quaternion, Vector3 } from 'three'
import type { Position3, RoofMode } from '../domain/types'

const unit = new BoxGeometry(1, 1, 1)
const noRaycast = () => {}
type Segment = { position: Position3; size: Position3; angle?: number }

/** One roof, three visual states. No positions or operational data are changed. */
export default memo(function Roof({ mode }: { mode: RoofMode }) {
  const root = useRef<Group>(null)
  const panels = useRef<InstancedMesh>(null), structure = useRef<InstancedMesh>(null)
  const { invalidate } = useThree()
  const opacity = useRef(mode === 'closed' ? 1 : mode === 'translucent' ? .17 : 0)
  const reduced = useRef(false)
  const materials = useMemo(() => [
    new MeshStandardMaterial({ color: '#87939e', roughness: .66, metalness: .32 }),
    new MeshStandardMaterial({ color: '#73808a', roughness: .74, metalness: .24 }),
  ], [])
  const segments = useMemo(() => {
    const sheet: Segment[] = [], steel: Segment[] = []
    const angle = Math.atan2(2.5, 28), length = Math.hypot(28, 2.5)
    for (const side of [-1, 1]) {
      sheet.push({ position: [side * 14, 10.55, 0], size: [length + .6, .12, 36.8], angle: -side * angle })
      for (let i = 0; i < 42; i++) {
        const x = side * (.5 + i * .66)
        sheet.push({ position: [x, 11.8 - Math.abs(x) * 2.5 / 28 + .09, 0], size: [.055, .045, 36.8], angle: -side * angle })
      }
    }
    const beam = (a: Position3, b: Position3, thickness: number) => steel.push({
      position: [(a[0] + b[0]) / 2, (a[1] + b[1]) / 2, a[2]],
      size: [Math.hypot(b[0] - a[0], b[1] - a[1]), thickness, thickness], angle: Math.atan2(b[1] - a[1], b[0] - a[0]),
    })
    for (const z of [-9, 0, 9, 17]) {
      beam([-27.4, 9.1, z], [27.4, 9.1, z], .15)
      beam([-27.4, 9.3, z], [0, 11.8, z], .19)
      beam([0, 11.8, z], [27.4, 9.3, z], .19)
      for (let x = -27; x < 27; x += 4.5) {
        const y = 11.8 - Math.abs(x + 2.25) / 27.4 * 2.5
        beam([x, 9.1, z], [x + 2.25, y, z], .08)
        beam([x + 2.25, y, z], [x + 4.5, 9.1, z], .08)
      }
    }
    steel.push({ position: [0, 11.85, 0], size: [.24, .12, 37] })
    return [sheet, steel]
  }, [])
  useLayoutEffect(() => {
    ;[panels, structure].forEach((ref, group) => {
      const mesh = ref.current!
      segments[group].forEach((part, index) => mesh.setMatrixAt(index, new Matrix4().compose(new Vector3(...part.position), new Quaternion().setFromEuler(new Euler(0, 0, part.angle ?? 0)), new Vector3(...part.size))))
      mesh.instanceMatrix.needsUpdate = true
      mesh.computeBoundingSphere()
    })
  }, [segments])
  useEffect(() => {
    const preference = window.matchMedia('(prefers-reduced-motion: reduce)')
    const change = () => { reduced.current = preference.matches; invalidate() }
    change(); preference.addEventListener('change', change)
    return () => preference.removeEventListener('change', change)
  }, [invalidate])
  useEffect(() => { invalidate() }, [mode, invalidate])
  useEffect(() => () => materials.forEach(material => material.dispose()), [materials])
  useFrame((_, delta) => {
    const target = mode === 'closed' ? 1 : mode === 'translucent' ? .17 : 0
    opacity.current += (target - opacity.current) * (reduced.current ? 1 : 1 - Math.exp(-Math.min(delta, .1) * 8))
    const done = Math.abs(target - opacity.current) < .002
    if (done) opacity.current = target
    if (root.current) root.current.visible = opacity.current > .001
    materials.forEach(material => {
      const transparent = opacity.current < .999
      if (material.transparent !== transparent) { material.transparent = transparent; material.needsUpdate = true }
      material.opacity = opacity.current
      material.depthWrite = !transparent
    })
    if (panels.current) panels.current.castShadow = opacity.current === 1
    if (structure.current) structure.current.castShadow = opacity.current === 1
    if (!done) invalidate()
  })
  return <group ref={root} name="Cobertura da oficina" visible={opacity.current > 0}>
    <instancedMesh ref={panels} args={[unit, materials[0], segments[0].length]} raycast={noRaycast} receiveShadow dispose={null}/>
    <instancedMesh ref={structure} args={[unit, materials[1], segments[1].length]} raycast={noRaycast} receiveShadow dispose={null}/>
  </group>
})

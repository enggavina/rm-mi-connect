import { Suspense, memo, useEffect, useRef, useState } from 'react'
import { useFrame, useThree } from '@react-three/fiber'
import { useTexture } from '@react-three/drei'
import { Group, Mesh, SRGBColorSpace } from 'three'
import type { Position3 } from '../domain/types'
import { Box, BoxBatch, colors } from './IndustrialModels'
import { advanceCraneClock, getCranePose } from './craneTimeline'
import type { CraneClock } from './craneTimeline'

/** The supplied vector artwork is used intact; no recreated MI lettering. */
export function LogoPlate({ position, rotation = [0, 0, 0], width = 1.4 }: { position: Position3; rotation?: Position3; width?: number }) {
  const texture = useTexture('/workshop/brand/mi-logo.svg')
  texture.colorSpace = SRGBColorSpace
  const height = width * 287.86 / 293
  return <group position={position} rotation={rotation}>
    <Box size={[width + .12, height + .12, .055]} color="#fffef9" roughness={.75} />
    <mesh position={[0, 0, .03]}><planeGeometry args={[width, height]} /><meshBasicMaterial map={texture} transparent toneMapped={false} /></mesh>
  </group>
}

const FixedRails = memo(function FixedRails() {
  return <BoxBatch>
    {[-16.4, 16.4].map(z => <group key={z}>
      <Box position={[0, 6.85, z]} size={[54.5, .42, .55]} color="#8b979b" />
      <Box position={[0, 7.11, z]} size={[54.6, .12, .19]} color="#465962" metalness={.6} />
      {[-26.2, -13.1, 0, 13.1, 26.2].map(x => <group key={x} position={[x, 0, z]}>
        <Box position={[0, 3.4, 0]} size={[.48, 6.8, .48]} color="#aeb7b7" />
        <Box position={[0, 6.57, 0]} size={[1.1, .16, .9]} color="#88989a" />
        <Box position={[0, .3, 0]} size={[.82, .6, .85]} color={colors.yellow} />
        {[-.2, .2].map(offset => <Box key={offset} position={[offset, .3, .43]} size={[.13, .58, .02]} color="#1c2d35" rotation={[0, 0, -.35]} />)}
      </group>)}
    </group>)}
    {[-.4, .4].map(x => <Box key={x} position={[-25.5 + x, 3.5, 16.75]} size={[.07, 6.5, .07]} color={colors.yellow} />)}
    {Array.from({ length: 13 }, (_, i) => <Box key={i} position={[-25.5, .5 + i * .5, 16.75]} size={[.8, .065, .07]} color={colors.yellow} />)}
  </BoxBatch>
})

/** One bridge spans Z and travels along X. Columns and runway beams are fixed.
 * Moving groups are siblings of each static BoxBatch, never baked into it. */
export default function Crane({ animationRunning = false }: { animationRunning?: boolean }) {
  const bridge = useRef<Group>(null), trolley = useRef<Group>(null), hook = useRef<Group>(null)
  const cableA = useRef<Mesh>(null), cableB = useRef<Mesh>(null)
  const clock = useRef<CraneClock>({ elapsed: 0, primed: false })
  const { invalidate } = useThree()
  const [eligible, setEligible] = useState(() => !document.hidden && !window.matchMedia('(prefers-reduced-motion: reduce)').matches)
  useEffect(() => {
    const preference = window.matchMedia('(prefers-reduced-motion: reduce)')
    const update = () => { clock.current.primed = false; setEligible(!document.hidden && !preference.matches); invalidate() }
    preference.addEventListener('change', update)
    document.addEventListener('visibilitychange', update)
    return () => { preference.removeEventListener('change', update); document.removeEventListener('visibilitychange', update) }
  }, [invalidate])
  useEffect(() => { clock.current.primed = false; invalidate() }, [animationRunning, eligible, invalidate])
  useFrame((_, delta) => {
    clock.current = advanceCraneClock(clock.current, delta, { running: animationRunning, visible: !document.hidden, reducedMotion: !eligible })
    const pose = getCranePose(clock.current.elapsed)
    if (bridge.current) bridge.current.position.x = pose.bridgeX
    if (trolley.current) trolley.current.position.z = pose.trolleyZ
    if (hook.current) hook.current.position.y = -pose.hookDrop
    for (const cable of [cableA.current, cableB.current]) if (cable) { cable.position.y = -pose.hookDrop / 2; cable.scale.y = pose.hookDrop }
    if (animationRunning && eligible && !document.hidden) invalidate()
  })
  const initial = getCranePose(0)
  return <group name="Ponte única — movimento ilustrativo independente da operação">
    <FixedRails />
    <group ref={bridge} position={[initial.bridgeX, 0, 0]} name="Travessão Z — translação X">
      <BoxBatch>
        <Box position={[0, 7.56, 0]} size={[.8, .78, 33.7]} color={colors.yellow} roughness={.46} />
        <Box position={[0, 7.99, 0]} size={[1.1, .12, 34]} color={colors.yellowLight} />
        <Box position={[0, 7.12, 0]} size={[1.05, .12, 34]} color="#c99b1d" />
        {[-16.4, 16.4].map(z => <group key={z} position={[0, 0, z]}>
          <Box position={[0, 7.37, 0]} size={[2.3, .48, .85]} color={colors.yellow} />
          {[-.75, .75].map(x => <Box key={x} position={[x, 7.16, 0]} size={[.34, .23, .4]} color="#354750" />)}
        </group>)}
      </BoxBatch>
      <Suspense fallback={null}><LogoPlate position={[.43, 7.58, 5.2]} rotation={[0, Math.PI / 2, 0]} width={1.3} /></Suspense>
      <group ref={trolley} position={[0, 8.2, initial.trolleyZ]} name="Carro — translação Z">
        <BoxBatch>
          <Box size={[1.65, .25, 2]} color={colors.yellow} />
          <Box position={[0, .4, 0]} size={[1.18, .62, 1.2]} color="#283f4f" />
          <Box position={[.77, .3, 0]} size={[.3, .48, .9]} color="#677a81" />
        </BoxBatch>
        {([cableA, cableB] as const).map((ref, index) => <mesh key={index} ref={ref} position={[index ? .25 : -.25, -initial.hookDrop / 2, 0]} scale={[1, initial.hookDrop, 1]}><cylinderGeometry args={[.018, .018, 1, 7]} /><meshStandardMaterial color="#3b4c53" metalness={.6} roughness={.5} /></mesh>)}
        <group ref={hook} position={[0, -initial.hookDrop, 0]} name="Gancho — movimento vertical">
          <Box position={[0, -.12, 0]} size={[.65, .42, .42]} color={colors.yellow} />
          <mesh position={[.08, -.5, 0]} rotation={[0, 0, Math.PI / 5]} castShadow><torusGeometry args={[.24, .07, 8, 20, Math.PI * 1.5]} /><meshStandardMaterial color="#34454e" metalness={.65} roughness={.4} /></mesh>
        </group>
      </group>
    </group>
  </group>
}

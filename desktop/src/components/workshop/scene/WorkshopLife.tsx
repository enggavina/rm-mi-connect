import { useEffect, useLayoutEffect, useMemo, useRef, useState } from 'react'
import type { MutableRefObject } from 'react'
import { useFrame, useThree } from '@react-three/fiber'
import { BoxGeometry, Color, CylinderGeometry, Group, InstancedBufferAttribute, InstancedMesh, Matrix4, MeshStandardMaterial, Quaternion, SphereGeometry, Vector3 } from 'three'
import { Box, BoxBatch } from './IndustrialModels'
import { BrandDecal } from './BrandDecal'
import { logisticsFrame } from './logisticsTimeline'
import type { FlowFrame, RoutePose } from './logisticsTimeline'
import { advancePedestrians, createPedestrians, WALKING_STAFF_COUNT } from './peopleSimulation'
import { testRoomOperators } from './TestRoom'

export interface WorkshopLifeProps { enabled: boolean; workers: boolean; logistics: boolean }
interface VisualClock { time: number; delta: number; active: boolean }
type ClockRef = MutableRefObject<VisualClock>
const unitBox = new BoxGeometry(1, 1, 1)
const round = new SphereGeometry(1, 10, 6)
const tire = new CylinderGeometry(1, 1, 1, 12)
const workerMaterial = new MeshStandardMaterial({ color: '#ffffff', roughness: .88, metalness: .03 })
const rubberMaterial = new MeshStandardMaterial({ color: '#293739', roughness: .95 })
const rimMaterial = new MeshStandardMaterial({ color: '#aeb6ab', roughness: .55, metalness: .5 })
const helmetMaterial = new MeshStandardMaterial({ color: '#ffffff', roughness: .67 })
const workwear = { shirt: '#bcc2c3', sleeve: '#b0b8bb', trousers: '#a7b0b4', seam: '#748087', belt: '#4b565c', boots: '#30383d', helmet: '#f4f5f2' }
const Y_AXIS = new Vector3(0, 1, 0)
const X_AXIS = new Vector3(1, 0, 0)
const yawDelta = (a: number, b: number) => Math.atan2(Math.sin(b - a), Math.cos(b - a))

// Different jobs, gestures and independently routed people; never real staffing.
const workerPositions: { walking: boolean; x: number; z: number; yaw: number; job: string; floor?: number }[] = [
  ...Array.from({ length: WALKING_STAFF_COUNT }, () => ({ walking: true, x: 0, z: 0, yaw: 0, job: 'walk' })),
  { walking: false, x: -22, z: -4.95, yaw: Math.PI, job: 'repair' },
  { walking: false, x: -13.2, z: -4.95, yaw: Math.PI, job: 'inspect' },
  { walking: false, x: -4.4, z: -4.95, yaw: Math.PI, job: 'repair' },
  { walking: false, x: 13.2, z: -4.95, yaw: Math.PI, job: 'repair' },
  { walking: false, x: 24.1, z: -4.35, yaw: Math.PI, job: 'controls' },
  { walking: false, x: -4.4, z: 2.35, yaw: Math.PI, job: 'inspect' },
  { walking: false, x: 11.5, z: 1.5, yaw: Math.PI, job: 'repair' },
  { walking: false, x: -13.2, z: 2.35, yaw: Math.PI, job: 'repair' },
  { walking: false, x: 4.4, z: 9.65, yaw: Math.PI, job: 'controls' },
  { walking: false, x: -16, z: -12.5, yaw: Math.PI, job: 'controls' },
  // Dedicated test-room crew: operator, instrumentation and checklist.
  ...testRoomOperators.map(operator => ({ walking: false, x: operator.position[0], z: operator.position[2], floor: operator.position[1], yaw: operator.rotation, job: operator.pose === 'panel' ? 'controls' : operator.pose })),
]
interface PersonPart { position: [number, number, number]; size: [number, number, number]; color: string; joint?: 'leftArm' | 'rightArm' | 'leftLeg' | 'rightLeg' }
const personParts: PersonPart[] = [
  { position: [0, 1.08, 0], size: [.43, .46, .27], color: workwear.shirt },
  { position: [0, 1.23, .145], size: [.44, .1, .025], color: workwear.seam },
  { position: [0, 1.1, .148], size: [.43, .035, .02], color: '#dde0de' },
  { position: [0, 1.1, -.148], size: [.43, .035, .02], color: '#dde0de' },
  { position: [0, .85, 0], size: [.4, .06, .29], color: workwear.belt },
  { position: [0, 1.32, 0], size: [.13, .1, .13], color: 'skin' },
  { position: [0, 1.46, 0], size: [.23, .25, .23], color: 'skin' },
  { position: [0, 1.59, .015], size: [.34, .035, .33], color: workwear.helmet },
  { position: [0, -.23, 0], size: [.15, .45, .17], color: workwear.sleeve, joint: 'leftArm' },
  { position: [0, -.48, .005], size: [.13, .13, .14], color: 'skin', joint: 'leftArm' },
  { position: [0, -.23, 0], size: [.15, .45, .17], color: workwear.sleeve, joint: 'rightArm' },
  { position: [0, -.48, .005], size: [.13, .13, .14], color: 'skin', joint: 'rightArm' },
  { position: [0, -.29, 0], size: [.16, .61, .2], color: workwear.trousers, joint: 'leftLeg' },
  { position: [0, -.67, .06], size: [.2, .16, .32], color: workwear.boots, joint: 'leftLeg' },
  { position: [0, -.29, 0], size: [.16, .61, .2], color: workwear.trousers, joint: 'rightLeg' },
  { position: [0, -.67, .06], size: [.2, .16, .32], color: workwear.boots, joint: 'rightLeg' },
]
const pivots = { leftArm: [-.28, 1.26, 0], rightArm: [.28, 1.26, 0], leftLeg: [-.12, .84, 0], rightLeg: [.12, .84, 0] } as const

/** All bodies and helmets are drawn in two instanced calls, including limbs. */
function Workers({ clock, visible }: { clock: ClockRef; visible: boolean }) {
  const bodies = useRef<InstancedMesh>(null), helmets = useRef<InstancedMesh>(null)
  const pedestrians = useMemo(() => createPedestrians(), [])
  const headings = useRef(workerPositions.map((worker, i) => worker.walking ? pedestrians.people[i].pose.yaw : worker.yaw))
  const temp = useMemo(() => ({ root: new Matrix4(), joint: new Matrix4(), part: new Matrix4(), position: new Vector3(), scale: new Vector3(), rotation: new Quaternion(), jointRotation: new Quaternion() }), [])
  const instanceColors = useMemo(() => {
    const skin = ['#b68a69', '#785c4b', '#c29a78', '#9a7459', '#b18d70', '#765c4e']
    const bodyColors = new Float32Array(workerPositions.length * personParts.length * 3)
    const helmetColors = new Float32Array(workerPositions.length * 3)
    workerPositions.forEach((_, person) => {
      personParts.forEach((part, index) => new Color(part.color === 'skin' ? skin[person % skin.length] : part.color).toArray(bodyColors, (person * personParts.length + index) * 3))
      new Color(workwear.helmet).toArray(helmetColors, person * 3)
    })
    return { bodies: new InstancedBufferAttribute(bodyColors, 3), helmets: new InstancedBufferAttribute(helmetColors, 3) }
  }, [])
  useLayoutEffect(() => {
    // Bind instanceColor before the first shader is compiled. Explicitly refresh
    // both the attributes and shader so a previous white material cannot persist.
    instanceColors.bodies.needsUpdate = true
    instanceColors.helmets.needsUpdate = true
    workerMaterial.needsUpdate = true
    helmetMaterial.needsUpdate = true
  }, [instanceColors])
  useFrame(() => {
    if (!bodies.current || !helmets.current || !visible) return
    const { time, delta } = clock.current
    const walkingPoses = advancePedestrians(pedestrians, delta)
    workerPositions.forEach((worker, person) => {
      const pose = worker.walking ? walkingPoses[person] : { x: worker.x, z: worker.z, yaw: worker.yaw, walking: 0, action: worker.job }
      headings.current[person] += yawDelta(headings.current[person], pose.yaw) * (1 - Math.exp(-delta * 11))
      const rhythm = time * (5.4 + person % 4 * .43) + person * 1.7
      const swing = Math.sin(rhythm) * .38 * pose.walking
      const bob = worker.walking ? Math.abs(Math.sin(rhythm)) * .018 * pose.walking : Math.sin(time * .7 + person) * .007
      const working = Math.sin(time * (1.3 + person % 3 * .4) + person * 2)
      const checking = pose.action === 'checking' || worker.job === 'checklist' || worker.job === 'inspect'
      const angles = {
        leftLeg: swing, rightLeg: -swing,
        leftArm: pose.walking ? -swing * .75 : checking ? -1.15 + working * .04 : worker.job === 'controls' ? -.45 : -.85 + working * .18,
        rightArm: pose.walking ? swing * .75 : checking ? -.95 + working * .12 : worker.job === 'controls' ? -1.05 + working * .22 : -.65 - working * .14,
      }
      temp.root.compose(temp.position.set(pose.x, (worker.floor ?? .03) - .08 + bob, pose.z), temp.rotation.setFromAxisAngle(Y_AXIS, headings.current[person]), temp.scale.set(1, 1, 1))
      personParts.forEach((part, index) => {
        temp.part.compose(temp.position.set(...part.position), temp.rotation.identity(), temp.scale.set(...part.size))
        if (part.joint) {
          const pivot = pivots[part.joint]
          temp.joint.compose(temp.position.set(pivot[0], pivot[1], pivot[2]), temp.jointRotation.setFromAxisAngle(X_AXIS, angles[part.joint]), temp.scale.set(1, 1, 1))
          temp.part.premultiply(temp.joint)
        }
        temp.part.premultiply(temp.root)
        bodies.current!.setMatrixAt(person * personParts.length + index, temp.part)
      })
      temp.part.compose(temp.position.set(0, 1.62, 0), temp.rotation.identity(), temp.scale.set(.17, .105, .17)).premultiply(temp.root)
      helmets.current!.setMatrixAt(person, temp.part)
    })
    bodies.current.instanceMatrix.needsUpdate = true
    helmets.current.instanceMatrix.needsUpdate = true
  })
  return <group visible={visible} name="Funcionários ilustrativos — sem correspondência com pessoas reais">
    <instancedMesh ref={bodies} args={[unitBox, workerMaterial, workerPositions.length * personParts.length]} instanceColor={instanceColors.bodies} castShadow receiveShadow frustumCulled={false} />
    <instancedMesh ref={helmets} args={[round, helmetMaterial, workerPositions.length]} instanceColor={instanceColors.helmets} castShadow frustumCulled={false} />
  </group>
}

function Wheel({ x, z, radius = .38, width = .23 }: { x: number; z: number; radius?: number; width?: number }) {
  return <group position={[x, radius + .04, z]} rotation={[0, 0, Math.PI / 2]}>
    <mesh geometry={tire} material={rubberMaterial} scale={[radius, width, radius]} castShadow dispose={null} />
    <mesh geometry={tire} material={rimMaterial} scale={[radius * .48, width + .025, radius * .48]} dispose={null} />
  </group>
}
/** A generic wrapped parcel on a pallet. It is never bound to a service order. */
function PalletLoad() {
  return <BoxBatch>
    {[-.43, 0, .43].map(x => <Box key={x} position={[x, .055, 0]} size={[.16, .11, 1.12]} color="#8e7d5e" />)}
    {[-.46, -.23, 0, .23, .46].map(z => <Box key={z} position={[0, .14, z]} size={[1.2, .06, .17]} color="#b5a586" />)}
    <Box position={[0, .52, 0]} size={[1.03, .68, .95]} color="#a9a897" />
    {[-.3, .3].map(x => <Box key={x} position={[x, .52, 0]} size={[.045, .7, .97]} color="#4b6266" />)}
    <Box position={[0, .89, 0]} size={[1.04, .06, .96]} color="#b9b6a2" />
  </BoxBatch>
}
function TruckModel({ loadRef, loadSide = .4 }: { loadRef: MutableRefObject<Group | null>; loadSide?: number }) {
  return <group>
    <BoxBatch>
      <Box position={[0, .68, -.1]} size={[2.06, .24, 6.5]} color="#455155" />
      <Box position={[0, 1.02, -1.03]} size={[2.3, .24, 4.45]} color="#8d9490" />
      <Box position={[0, .92, -1.03]} size={[2.35, .16, 4.55]} color="#9e4943" />
      <Box position={[0, 1.68, 2.12]} size={[2.15, 1.62, 1.86]} color="#d6d0b6" />
      <Box position={[0, 1.27, 3.06]} size={[2.14, .54, .12]} color="#9b4540" />
      <Box position={[0, 2.11, 3.066]} size={[1.84, .57, .025]} color="#425e65" />
      <Box position={[0, 2.45, 2.07]} size={[2.22, .12, 2.02]} color="#c5bfa7" />
      <Box position={[0, .96, 3.17]} size={[2.26, .17, .14]} color="#78827c" />
      <Box position={[0, 1.29, 3.14]} size={[.76, .22, .025]} color="#39494d" />
      {[-1.08, 1.08].map(x => <group key={x}>
        <Box position={[x, 2.08, 2.12]} size={[.025, .6, 1.4]} color="#526b6e" />
        <Box position={[x, 1.56, 1.65]} size={[.035, .12, .31]} color="#a14640" />
        <Box position={[x * 1.16, 1.95, 2.94]} size={[.16, .31, .12]} color="#536366" />
      </group>)}
      {[-.76, .76].map(x => <group key={x}><Box position={[x, 1.18, 3.15]} size={[.38, .15, .04]} color="#ece6c4" /><Box position={[x, 1.03, -3.32]} size={[.24, .1, .045]} color="#b84841" /></group>)}
    </BoxBatch>
    {[-1, 1].map(side => <BrandDecal key={side} src="/workshop/brand/mi-symbol.svg" position={[side * 1.101, 1.38, 2.25]} rotation={[0, side * Math.PI / 2, 0]} width={.64} />)}
    {[-1.12, 1.12].map(x => [-2.3, -1.25, 2.17].map(z => <Wheel key={String(x) + z} x={x} z={z} radius={.43} width={.26} />))}
    <group ref={loadRef} position={[loadSide, 1.15, -1.2]}><PalletLoad /></group>
  </group>
}
function ForkliftModel({ carriageRef, loadRef }: { carriageRef: MutableRefObject<Group | null>; loadRef: MutableRefObject<Group | null> }) {
  return <group>
    <BoxBatch>
      <Box position={[0, .49, -.18]} size={[1.2, .57, 1.66]} color="#c8a335" />
      <Box position={[0, .68, -.81]} size={[1.18, .78, .35]} color="#d2b34a" />
      <Box position={[0, .83, -.05]} size={[1.08, .13, 1.3]} color="#6c7669" />
      <Box position={[0, 1.08, -.46]} size={[.59, .24, .54]} color="#3c4a4c" />
      <Box position={[0, 1.35, -.71]} size={[.59, .56, .13]} color="#3c4a4c" />
      {[-.53, .53].map(x => [-.69, .57].map(z => <Box key={String(x) + z} position={[x, 1.57, z]} size={[.065, 1.37, .065]} color="#4c5a56" />))}
      <Box position={[0, 2.23, -.06]} size={[1.23, .09, 1.49]} color="#b9a147" />
      {[-.4, .4].map(x => <Box key={x} position={[x, 1.2, .84]} size={[.13, 2.3, .15]} color="#435457" />)}
      <Box position={[0, 2.32, .84]} size={[.95, .12, .17]} color="#4b5c5c" />
      <Box position={[0, .68, .91]} size={[.075, 1.1, .08]} color="#a8b1aa" />
      <Box position={[0, 1.33, .3]} size={[.4, .09, .3]} rotation={[-.5, 0, 0]} color="#384b50" />
      {/* Anonymous seated operator with workwear and a hard hat. */}
      <Box position={[0, 1.42, -.37]} size={[.4, .43, .26]} color={workwear.shirt} />
      <Box position={[0, 1.49, -.22]} size={[.4, .08, .02]} color={workwear.seam} />
      <Box position={[0, 1.77, -.37]} size={[.22, .25, .22]} color="#987359" />
      <Box position={[0, 1.93, -.37]} size={[.34, .08, .32]} color={workwear.helmet} />
      {[-.12, .12].map(x => <group key={x}>
        <Box position={[x, 1.15, -.12]} size={[.17, .16, .48]} color={workwear.trousers} />
        <Box position={[x, .94, .06]} size={[.16, .36, .17]} color={workwear.trousers} />
      </group>)}
    </BoxBatch>
    {[-.62, .62].map(x => [-.59, .53].map(z => <Wheel key={String(x) + z} x={x} z={z} radius={z > 0 ? .31 : .25} width={.19} />))}
    <group ref={carriageRef} position={[0, .35, 0]}>
      <BoxBatch>
        <Box position={[0, .36, .92]} size={[1.04, .77, .08]} color="#46595b" />
        {[-.37, .37].map(x => <Box key={x} position={[x, .025, 1.6]} size={[.13, .055, 1.54]} color="#73817b" />)}
      </BoxBatch>
      <group ref={loadRef} position={[0, .07, 1.8]}><PalletLoad /></group>
    </group>
  </group>
}
function positionModel(group: Group | null, pose: RoutePose, delta: number) {
  if (!group) return
  group.position.set(pose.x, .055, pose.z)
  group.rotation.y += yawDelta(group.rotation.y, pose.yaw) * (1 - Math.exp(-Math.max(delta, 0) * 10))
}
function Freight({ clock, visible }: { clock: ClockRef; visible: boolean }) {
  const truckIn = useRef<Group>(null), truckOut = useRef<Group>(null), forkIn = useRef<Group>(null), forkOut = useRef<Group>(null)
  const truckLoadIn = useRef<Group>(null), truckLoadOut = useRef<Group>(null), forkLoadIn = useRef<Group>(null), forkLoadOut = useRef<Group>(null)
  const carriageIn = useRef<Group>(null), carriageOut = useRef<Group>(null), stockLoad = useRef<Group>(null), dispatchLoad = useRef<Group>(null)
  const initial = useMemo(() => logisticsFrame(0), [])
  useFrame(() => {
    if (!visible) return
    const { incoming, outgoing } = logisticsFrame(clock.current.time)
    const update = (flow: FlowFrame, truck: Group | null, forklift: Group | null, truckCargo: Group | null, forkCargo: Group | null, carriage: Group | null, depot: Group | null) => {
      if (truck) truck.visible = flow.truckVisible
      if (truckCargo) truckCargo.visible = flow.truckLoaded
      if (forkCargo) forkCargo.visible = flow.forkLoaded
      if (depot) depot.visible = flow.depotLoaded
      if (carriage) carriage.position.y = flow.forkHeight
      positionModel(truck, flow.truck, clock.current.delta)
      positionModel(forklift, flow.forklift, clock.current.delta)
    }
    update(incoming, truckIn.current, forkIn.current, truckLoadIn.current, forkLoadIn.current, carriageIn.current, stockLoad.current)
    update(outgoing, truckOut.current, forkOut.current, truckLoadOut.current, forkLoadOut.current, carriageOut.current, dispatchLoad.current)
  })
  return <group visible={visible} name="Ciclo logístico ilustrativo — cargas genéricas">
    <group ref={truckIn} position={[initial.incoming.truck.x, .055, initial.incoming.truck.z]} rotation={[0, Math.PI / 2, 0]}><TruckModel loadRef={truckLoadIn} /></group>
    <group ref={truckOut} visible={false} position={[20, .055, 23.5]} rotation={[0, -Math.PI / 2, 0]}><TruckModel loadRef={truckLoadOut} loadSide={-.4} /></group>
    <group ref={forkIn} position={[-20, .055, 18.5]} rotation={[0, -Math.PI / 2, 0]}><ForkliftModel carriageRef={carriageIn} loadRef={forkLoadIn} /></group>
    <group ref={forkOut} position={[24, .055, 18.5]} rotation={[0, Math.PI / 2, 0]}><ForkliftModel carriageRef={carriageOut} loadRef={forkLoadOut} /></group>
    <group ref={stockLoad} visible={false} position={[-7, .125, 15.35]}><PalletLoad /></group>
    <group ref={dispatchLoad} position={[20, .125, 15.35]}><PalletLoad /></group>
  </group>
}

/**
 * Mount once under Canvas. enabled pauses the shared visual clock; toggling
 * workers/logistics only changes visibility. Keep mounted to preserve progress.
 * Reduced-motion and hidden tabs suspend animation without advancing time.
 */
export function WorkshopLife({ enabled, workers, logistics }: WorkshopLifeProps) {
  const { invalidate } = useThree()
  const clock = useRef<VisualClock>({ time: 0, delta: 0, active: false })
  const [eligible, setEligible] = useState(() => !document.hidden && !window.matchMedia('(prefers-reduced-motion: reduce)').matches)
  const firstFrame = useRef(true)
  useEffect(() => {
    const media = window.matchMedia('(prefers-reduced-motion: reduce)')
    const update = () => { setEligible(!document.hidden && !media.matches); firstFrame.current = true; invalidate() }
    document.addEventListener('visibilitychange', update)
    media.addEventListener('change', update)
    return () => { document.removeEventListener('visibilitychange', update); media.removeEventListener('change', update) }
  }, [invalidate])
  const active = enabled && eligible && (workers || logistics)
  useEffect(() => { clock.current.active = active; clock.current.delta = 0; firstFrame.current = true; invalidate() }, [active, workers, logistics, invalidate])
  useFrame((_, dt) => {
    const running = active && !document.hidden
    const delta = running && !firstFrame.current ? Math.min(.05, Math.max(0, dt)) : 0
    clock.current.delta = delta
    clock.current.time += delta
    if (running) { firstFrame.current = false; invalidate() }
  })
  return <group name="Simulação visual — não representa eventos operacionais">
    <Workers clock={clock} visible={workers} />
    <Freight clock={clock} visible={logistics} />
  </group>
}
export default WorkshopLife

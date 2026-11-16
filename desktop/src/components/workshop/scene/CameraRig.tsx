import { useEffect, useRef, useState } from 'react'
import { useFrame, useThree } from '@react-three/fiber'
import { OrbitControls } from '@react-three/drei'
import { MOUSE, OrthographicCamera, Vector3 } from 'three'
import type { OrbitControls as OrbitControlsImpl } from 'three-stdlib'
import type { Position3, SceneProps } from '../domain/types'
import { getWorkshopFrame } from './cameraFraming'

export default function CameraRig({ command, selectedPosition }: { command: SceneProps['cameraCommand']; selectedPosition: Position3 | undefined }) {
  const { camera, size, invalidate } = useThree()
  const controls = useRef<OrbitControlsImpl>(null)
  const previousSize = useRef<{ width: number; height: number } | null>(null)
  const transition = useRef<{ position: Vector3; target: Vector3; zoom: number } | null>(null)
  const [reducedMotion, setReducedMotion] = useState(() => window.matchMedia('(prefers-reduced-motion: reduce)').matches)
  const frame = getWorkshopFrame(size.width, size.height)
  useEffect(() => {
    const preference = window.matchMedia('(prefers-reduced-motion: reduce)')
    const update = () => { setReducedMotion(preference.matches); invalidate() }
    preference.addEventListener('change', update)
    return () => preference.removeEventListener('change', update)
  }, [invalidate])
  useEffect(() => {
    const cam = camera as OrthographicCamera, control = controls.current
    if (!control) return
    const previous = previousSize.current
    if (!previous) {
      const next = getWorkshopFrame(size.width, size.height)
      cam.zoom = next.zoom
      cam.position.copy(next.position); control.target.copy(next.target)
    } else {
      // Opening a selection panel changes canvas width; it must not reset the orbit.
      cam.zoom = Math.max(2, Math.min(110, cam.zoom * Math.min(size.width / previous.width, size.height / previous.height)))
    }
    previousSize.current = { width: size.width, height: size.height }
    cam.updateProjectionMatrix(); control.update(); transition.current = null; invalidate()
  }, [size.width, size.height, camera, invalidate])
  useEffect(() => {
    const control = controls.current
    if (!control) return
    const cam = camera as OrthographicCamera
    const target = control.target.clone(), position = cam.position.clone()
    let zoom = cam.zoom
    if (command.type === 'reset') {
      target.copy(frame.target); position.copy(frame.position); zoom = frame.zoom
    } else if (command.type === 'focus' && selectedPosition) {
      target.set(...selectedPosition); position.copy(target).add(cam.position.clone().sub(control.target)); zoom = Math.min(90, frame.zoom * 2.5)
    } else if (command.type === 'zoom-in') zoom = Math.min(110, zoom * 1.25)
    else if (command.type === 'zoom-out') zoom = Math.max(2, zoom / 1.25)
    else if (command.type === 'rotate') position.copy(target).add(position.clone().sub(target).applyAxisAngle(new Vector3(0, 1, 0), Math.PI / 4))
    if (reducedMotion) {
      transition.current = null; cam.position.copy(position); control.target.copy(target); cam.zoom = zoom; cam.updateProjectionMatrix(); control.update()
    } else transition.current = { position, target, zoom }
    invalidate()
    // Only explicit camera commands move the view; selection and filters never do.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [command.seq])
  useFrame((_, delta) => {
    if (!transition.current || !controls.current) return
    const cam = camera as OrthographicCamera, goal = transition.current
    const step = reducedMotion ? 1 : 1 - Math.exp(-Math.min(delta, .1) * 9)
    cam.position.lerp(goal.position, step); controls.current.target.lerp(goal.target, step)
    cam.zoom += (goal.zoom - cam.zoom) * step
    cam.updateProjectionMatrix(); controls.current.update()
    if (cam.position.distanceTo(goal.position) < .015 && controls.current.target.distanceTo(goal.target) < .015 && Math.abs(cam.zoom - goal.zoom) < .015) {
      cam.position.copy(goal.position); controls.current.target.copy(goal.target); cam.zoom = goal.zoom
      cam.updateProjectionMatrix(); controls.current.update(); transition.current = null
    } else invalidate()
  })
  return <OrbitControls ref={controls} makeDefault enableDamping={!reducedMotion} dampingFactor={.12} minPolarAngle={.3} maxPolarAngle={Math.PI / 2.18} minZoom={2} maxZoom={110} mouseButtons={{ LEFT: MOUSE.ROTATE, MIDDLE: MOUSE.DOLLY, RIGHT: MOUSE.PAN }} onStart={() => { transition.current = null }}/>
}

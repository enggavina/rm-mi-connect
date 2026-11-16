import { Vector3 } from 'three'
import { workshopBounds } from '../data/layout'

export const isometricOffset = new Vector3(44, 38, 56)

/** Architectural bounds alone drive framing; never filters, pages or backlog. */
export function getWorkshopFrame(width: number, height: number) {
  const view = isometricOffset.clone().normalize()
  const right = new Vector3(0, 1, 0).cross(view).normalize()
  const up = view.clone().cross(right).normalize()
  const points: Vector3[] = []
  for (const x of [-workshopBounds.width / 2, workshopBounds.width / 2])
    for (const z of [-workshopBounds.depth / 2, workshopBounds.depth / 2])
      for (const y of [0, workshopBounds.height]) points.push(new Vector3(x, y, z))
  const xs = points.map(p => p.dot(right)), ys = points.map(p => p.dot(up))
  const projectedWidth = Math.max(...xs) - Math.min(...xs)
  const projectedHeight = Math.max(...ys) - Math.min(...ys)
  const usableWidth = Math.max(180, width - 68)
  const usableHeight = Math.max(180, height - 144)
  const zoom = Math.max(2, Math.min(usableWidth * .73 / projectedWidth, usableHeight / projectedHeight))
  // Slight optical shift leaves the camera controls clear and shows the loading apron.
  const target = new Vector3(0, 3.1, 1.4).addScaledVector(right, 12 / zoom)
  return { target, position: target.clone().add(isometricOffset), zoom, projectedWidth, projectedHeight, usableWidth, usableHeight }
}

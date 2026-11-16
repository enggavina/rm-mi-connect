import { useEffect, useMemo, useRef, useState } from 'react'
import { Canvas } from '@react-three/fiber'
import { Html, useCursor } from '@react-three/drei'
import { ACESFilmicToneMapping, PCFSoftShadowMap } from 'three'
import type { SceneProps, WorkshopResource } from '../domain/types'
import { deadlineLabels, getDeadlineStatus, isOpenOrder, statusColors } from '../domain/metrics'
import { getDisplayModelScale, placeOrders } from '../domain/placement'
import type { MotorPlacement } from '../domain/placement'
import { resolveProductionCells } from '../data/layout'
import { ProductionCells } from './ProductionCells'
import WorkshopLife from './WorkshopLife'
import { Architecture } from './Architecture'
import Surroundings from './Surroundings'
import { Bench, Box, MotorModel, colors } from './IndustrialModels'
import { getOrderColor } from './getOrderColor'
import CameraRig from './CameraRig'
import './scene.css'

function Resource({ resource, selected, mode, orderCount, showLabel, illustrativeOnly, onSelect }: { resource: WorkshopResource; selected: boolean; mode: SceneProps['mode']; orderCount: number; showLabel: boolean; illustrativeOnly?: boolean; onSelect: () => void }) {
  const overloaded = resource.capacity !== null && orderCount > resource.capacity
  const capacityColor = illustrativeOnly ? statusColors.muted : overloaded ? statusColors.danger : orderCount ? statusColors.success : statusColors.muted
  return <group position={resource.position} rotation={[0, resource.rotation, 0]} onClick={event => { event.stopPropagation(); onSelect() }}>
    <Bench kind={resource.kind} />
    {(selected || mode === 'capacity') && <mesh position={[0, .09, 0]} rotation={[-Math.PI / 2, 0, 0]}><planeGeometry args={[3.8, 2.6]} /><meshStandardMaterial color={selected ? '#ec3c44' : capacityColor} transparent opacity={.36} roughness={1} depthWrite={false} /></mesh>}
    {showLabel && (mode === 'capacity' || selected) && <Html position={[0, .38, 1.2]} center distanceFactor={undefined} zIndexRange={[4, 0]}>
      <button className={`resource-tag ${selected ? 'is-selected' : ''}`} onClick={event => { event.stopPropagation(); onSelect() }} aria-label={`Selecionar ${resource.name}`}>
        {resource.id}{mode === 'capacity' && <span>{illustrativeOnly ? 'ilustrativo' : `${orderCount}/${resource.capacity ?? '—'}`}</span>}
      </button>
    </Html>}
  </group>
}

function OperationalMotor({ placement, selected, hovered, props, onHover }: { placement: MotorPlacement; selected: boolean; hovered: boolean; props: SceneProps; onHover: (id: string | null) => void }) {
  const { order, position, rotation, unsupported } = placement
  const deadline = getDeadlineStatus(order, props.referenceAt, props.soonDays)
  const accent = getOrderColor(order, props.mode, deadline)
  const modelScale = getDisplayModelScale(order, placement.scale)
  const statusText = props.mode === 'stages' ? order.stage ?? 'Etapa indisponível' : props.mode === 'blocks' ? order.blockDeclared ? 'Bloqueio declarado' : order.blockDeclared === false ? 'Sem bloqueio declarado' : 'Bloqueio não informado' : deadlineLabels[deadline]
  return <group position={position} onClick={event => { event.stopPropagation(); props.onSelect(order.id) }} onPointerOver={event => { event.stopPropagation(); onHover(order.id) }} onPointerOut={() => onHover(null)}>
    {placement.supportHeight === .14 && <group position={[0, -position[1], 0]} rotation={[0, rotation, 0]}>
      <Box position={[0, .105, 0]} size={[1.95, .07, 1.05]} color="#74808a" roughness={.9}/>
      {[-.7, .7].map(x => <Box key={x} position={[x, .035, 0]} size={[.15, .07, .95]} color="#48535d"/>)}
    </group>}
    <group rotation={[0, rotation, 0]}>
      <MotorModel kind={order.model} size={modelScale} color={selected || hovered ? '#278bd2' : colors.blue} />
      {/* Generous transparent hit target preserves selection for thin shafts and rotors. */}
      <mesh><boxGeometry args={[3.3 * placement.scale, 1.5 * placement.scale, 1.55 * placement.scale]} /><meshBasicMaterial transparent opacity={0} depthWrite={false} /></mesh>
    </group>
    {(selected || hovered) && <mesh position={[0, -position[1] + .15, 0]} rotation={[-Math.PI / 2, 0, 0]}><ringGeometry args={[1.6 * placement.scale, 1.78 * placement.scale, 32]} /><meshBasicMaterial color={selected ? '#ec3c44' : statusColors.info} transparent opacity={.9} depthWrite={false} /></mesh>}
    <mesh position={[0, modelScale * 1.25, 0]}><sphereGeometry args={[.13, 10, 8]} /><meshBasicMaterial color={accent} /></mesh>
    {((props.layers.labels && (!placement.logical || props.orders.length <= 14)) || selected || hovered) && <Html position={[0, modelScale * 1.12, 0]} center zIndexRange={selected ? [12, 10] : [8, 1]}>
      <button className={`motor-tag ${selected ? 'is-selected' : ''} ${hovered ? 'is-hovered' : ''} ${unsupported ? 'is-unlocated' : ''}`} style={{ '--marker-color': accent } as React.CSSProperties} onClick={event => { event.stopPropagation(); props.onSelect(order.id) }} aria-label={`Selecionar ${order.code}: ${order.equipment}, ${statusText}`}>
        <span className="motor-tag-dot" /><strong>{order.code}</strong>{placement.copies > 1 && <span title="Mesmo projeto em atividades simultâneas">×{placement.copies}</span>}{order.blockDeclared === true && <span className="motor-tag-lock" aria-label="Bloqueado">!</span>}
        {(selected || hovered) && <span className="motor-tag-detail">{order.stage ?? 'Etapa não informada'}</span>}
      </button>
    </Html>}
  </group>
}

function SceneContent(props: SceneProps) {
  const [hoveredId, setHoveredId] = useState<string | null>(null)
  useCursor(hoveredId !== null)
  const cells = useMemo(() => props.resolvedCells ?? resolveProductionCells(props.catalog), [props.resolvedCells, props.catalog])
  const placements = useMemo(() => placeOrders(props.layoutOrders ?? props.allOrders ?? props.orders, props.resources, cells, props.placementMode ?? 'process', props.illustrativeOnly), [props.layoutOrders, props.allOrders, props.orders, props.resources, cells, props.placementMode, props.illustrativeOnly])
  const visibleIds = new Set(props.orders.map(order => order.id))
  const visiblePlacements = placements.filter(placement => !placement.unsupported && visibleIds.has(placement.order.id))
  const selected = visiblePlacements.find(placement => placement.order.id === props.selectedId)
  const selectedResource = props.resources.find(resource => resource.id === props.selectedResourceId)
  const selectedCell = cells.find(cell => cell.id === props.selectedCellId)
  const ready = useRef(props.onReady)
  useEffect(() => { ready.current?.() }, [])
  return <>
    <color attach="background" args={['#dfe4e7']} />
    <ambientLight intensity={.48} />
    <hemisphereLight args={['#eaf2ff', '#727b83', 1.15]} />
    <directionalLight position={[-26, 48, 32]} intensity={3.1} color="#fff0d8" castShadow shadow-mapSize={[2048, 2048]} shadow-camera-left={-54} shadow-camera-right={54} shadow-camera-top={50} shadow-camera-bottom={-50} shadow-radius={3} shadow-camera-far={110} shadow-bias={-.0003} shadow-normalBias={.04} />
    <directionalLight position={[-16, 9, -12]} intensity={.45} color="#d6e6ff" />
    <mesh rotation={[-Math.PI / 2, 0, 0]} position={[0, -.93, 0]} receiveShadow><planeGeometry args={[300, 300]} /><meshStandardMaterial color="#dfe4e7" roughness={1} /></mesh>
    <Surroundings />
    <Architecture layers={props.layers} animationRunning={props.animationRunning ?? false} testRoomOccupied={visiblePlacements.some(placement => placement.cellId === 'testes-finais')} />
    <ProductionCells cells={cells} orders={props.allOrders ?? props.orders} selectedCellId={props.selectedCellId ?? null} onSelectCell={props.onSelectCell ?? (() => {})} highlighted={props.layers.sectors} showLabels={props.layers.areaLabels}/>
    {props.resources.filter(resource => resource.sector !== 'Testes Finais' && (cells.find(cell => cell.name === resource.sector)?.kind === 'work' || resource.id === 'B-01')).map(resource => <Resource key={resource.id} resource={resource} selected={props.selectedResourceId === resource.id} mode={props.mode} orderCount={(props.allOrders ?? props.orders).filter(order => order.locationId === resource.id && isOpenOrder(order)).length} showLabel={props.layers.labels} illustrativeOnly={props.illustrativeOnly} onSelect={() => props.onSelectResource(resource.id)} />)}
    <WorkshopLife enabled={props.animationRunning ?? false} workers={props.showWorkers ?? true} logistics={props.showLogistics ?? true}/>
    {visiblePlacements.map(placement => <OperationalMotor key={placement.key} placement={placement} selected={props.selectedId === placement.order.id} hovered={hoveredId === placement.order.id} props={props} onHover={setHoveredId} />)}
    <CameraRig command={props.cameraCommand} selectedPosition={selected?.position ?? selectedResource?.position ?? selectedCell?.position} />
  </>
}

export default function WorkshopScene(props: SceneProps) {
  const [supported, setSupported] = useState<boolean | null>(null)
  useEffect(() => {
    try {
      const probe = document.createElement('canvas'), context = probe.getContext('webgl2')
      setSupported(!!context)
      context?.getExtension('WEBGL_lose_context')?.loseContext()
    } catch { setSupported(false) }
  }, [])
  if (supported !== true) return <div className="workshop-canvas"><div className="webgl-fallback" role="status">
    <p>{supported === null ? 'Preparando a visualização da oficina…' : 'A visualização 3D precisa de WebGL2. Consulte os mesmos projetos na visão gerencial.'}</p>
    {supported === false && props.onUnavailable && <button className="primary-button" onClick={props.onUnavailable}>Abrir visão gerencial</button>}
  </div></div>
  return <div className="workshop-canvas" aria-label="Modelo 3D ilustrativo da oficina MI Electric. Use os botões de câmera para navegar e a lista de ordens para seleção por teclado.">
    <Canvas orthographic frameloop="demand" shadows dpr={[1, 1.5]} camera={{ position: [42, 41.2, 51], zoom: 12, near: .1, far: 300 }} gl={{ antialias: true, alpha: false, powerPreference: 'high-performance' }} onCreated={({ gl }) => { gl.shadowMap.type = PCFSoftShadowMap; gl.toneMapping = ACESFilmicToneMapping; gl.toneMappingExposure = 1.06 }} onPointerMissed={() => props.onSelect(null)} fallback={<div className="webgl-fallback">A visualização 3D precisa de WebGL. As ordens continuam disponíveis na visão gerencial.</div>}>
      <SceneContent {...props} />
    </Canvas>
  </div>
}

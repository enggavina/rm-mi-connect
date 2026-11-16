import { Mouse, Move, RotateCw, ScanLine, X } from 'lucide-react'
import { useEffect, useRef } from 'react'
import { IconButton } from './ui'
export default function HelpDialog({ onClose }: { onClose: () => void }) {
  const dialog = useRef<HTMLDialogElement>(null)
  useEffect(() => { dialog.current?.showModal(); return () => dialog.current?.close() }, [])
  return <dialog ref={dialog} className="help-dialog" onCancel={onClose} onClick={e => { if (e.target === e.currentTarget) onClose() }}><div className="section-heading"><h2>A oficina, em suas mãos</h2><IconButton label="Fechar ajuda" onClick={onClose}><X size={20}/></IconButton></div><p>Explore a cena ou use a visão gerencial para navegar pelo teclado.</p><div className="help-actions"><div><Mouse/><span><b>Selecionar</b>Clique no equipamento ou na sua identificação.</span></div><div><Move/><span><b>Mover a vista</b>Arraste com o botão direito do mouse.</span></div><div><RotateCw/><span><b>Girar e aproximar</b>Arraste com o botão esquerdo. Use a roda para zoom.</span></div><div><ScanLine/><span><b>Voltar ao início</b>Use “Visão geral” nos controles da cena.</span></div></div><p className="micro-notice">Somente leitura. A navegação da câmera não movimenta equipamentos reais.</p><button className="primary-button" onClick={onClose}>Entendi, explorar a oficina</button></dialog>
}

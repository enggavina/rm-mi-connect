'use client';
import { useRef, useState } from 'react';
import { saveProject, planCell, type WebActionResult } from '@/server/web/actions';
import type { WebRow } from '@/server/web/data';
import { Icon } from './icons';

// A retry repeats the frozen request after an ambiguous transport response.
function useSave(action: (input: unknown) => Promise<WebActionResult>, done: (result: Extract<WebActionResult, { ok: true }>) => void) {
  const [busy, setBusy] = useState(false); const [error, setError] = useState(''); const [uncertain, setUncertain] = useState(false);
  const attempt = useRef<Record<string, unknown> | null>(null); const inFlight = useRef(false);
  async function submit(payload: Record<string, unknown>) {
    if (inFlight.current) return;
    inFlight.current = true; setBusy(true); setError('');
    if (!attempt.current) attempt.current = { ...payload, submissionId: crypto.randomUUID() };
    try {
      const result = await action(attempt.current);
      if (result.ok) { attempt.current = null; setUncertain(false); done(result); }
      else {
        setError(result.error + (result.fieldErrors ? ' ' + Object.keys(result.fieldErrors).join(', ') : ''));
        setUncertain(result.code === 'UNAVAILABLE');
        if (result.code !== 'UNAVAILABLE') attempt.current = null;
      }
    } catch { setUncertain(true); setError('A conexão foi interrompida. Tente confirmar novamente: o mesmo protocolo será usado para evitar duplicação.'); }
    finally { inFlight.current = false; setBusy(false); }
  }
  return { busy, error, uncertain, submit };
}

const nullable = (form: FormData, name: string) => String(form.get(name) ?? '').trim() || null;
// Date inputs represent a calendar day in Brazil, independent of the browser timezone.
const day = (value: FormDataEntryValue | null) => value ? `${String(value)}T12:00:00-03:00` : null;
const inputDay = (value: unknown) => value ? new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Sao_Paulo', year: 'numeric', month: '2-digit', day: '2-digit' }).format(new Date(String(value))) : '';

export function ProjectEditor({ project, clients, types, users, statuses, hasAllocations = false }: { project?: WebRow; clients: WebRow[]; types: WebRow[]; users: WebRow[]; statuses: WebRow[]; hasAllocations?: boolean }) {
  const [id] = useState(() => project?.id || crypto.randomUUID());
  const save = useSave(saveProject, result => { window.location.assign(`/projetos/${result.data.id}`); });
  const submit = (form: HTMLFormElement) => {
    const data = new FormData(form); const changes: Record<string, unknown> = {};
    for (const key of ['numero', 'nome', 'cliente_id', 'descricao_equipamento', 'escopo_abreviado', 'gestor_responsavel_id', 'contato', 'proprietario', 'eventualidades', 'replanejamento_motivo']) changes[key] = nullable(data, key);
    if (!hasAllocations) changes.tipo_equipamento_id = nullable(data, 'tipo_equipamento_id');
    changes.status_pcp = nullable(data, 'status_pcp');
    for (const key of ['data_prevista_inicio', 'data_prevista_final', 'data_contratual', 'data_renegociada']) {
      // Unchanged dates retain their original instant and precision.
      if (!project || String(data.get(key) || '') !== inputDay(project[key])) changes[key] = day(data.get(key));
    }
    void save.submit({ id, expected_updated_at: project?.updated_at ?? null, changes });
  };
  return <form onSubmit={event => { event.preventDefault(); submit(event.currentTarget); }}>
    {save.error && <div role="alert" className="notice error">{save.error}</div>}
    {save.uncertain && <div className="notice">Os campos permanecem protegidos até confirmar o resultado deste envio.</div>}
    <fieldset disabled={save.busy || save.uncertain} style={{ margin: 0, padding: 0, border: 0 }}><div className="form-grid">
      <div className="field"><label htmlFor="numero">Número da OS / projeto</label><input id="numero" name="numero" defaultValue={project?.numero || ''} maxLength={100} placeholder="Atribuído pelo planejamento" /></div>
      <div className="field"><label htmlFor="nome">Nome do projeto</label><input id="nome" name="nome" defaultValue={project?.nome || ''} maxLength={500} placeholder="Identificação do projeto" /></div>
      <div className="field"><label htmlFor="cliente_id">Cliente</label><select id="cliente_id" name="cliente_id" defaultValue={project?.cliente_id || ''}><option value="">Selecione o cliente</option>{clients.map(row => <option key={row.id} value={row.id}>{row.nome}</option>)}</select></div>
      <div className="field"><label htmlFor="tipo_equipamento_id">Tipo de equipamento</label><select id="tipo_equipamento_id" name="tipo_equipamento_id" defaultValue={project?.tipo_equipamento_id || ''} disabled={hasAllocations}><option value="">Selecione o tipo</option>{types.map(row => <option key={row.id} value={row.id}>{row.nome}</option>)}</select>{hasAllocations && <span className="form-note">O tipo é preservado porque o projeto já possui células alocadas.</span>}</div>
      <div className="field span-all"><label htmlFor="descricao_equipamento">Descrição do equipamento</label><textarea id="descricao_equipamento" name="descricao_equipamento" defaultValue={project?.descricao_equipamento || ''} maxLength={10000} /></div>
      <div className="field"><label htmlFor="status_pcp">Status PCP</label><select id="status_pcp" name="status_pcp" defaultValue={project ? project.status_pcp || '' : 'aguardando_recebimento_equipamento'}><option value="">Sem status definido</option>{statuses.map(row => <option key={row.id} value={row.option_key}>{row.bubble_display}</option>)}</select></div>
      <div className="field"><label htmlFor="gestor_responsavel_id">Gestor responsável</label><select id="gestor_responsavel_id" name="gestor_responsavel_id" defaultValue={project?.gestor_responsavel_id || ''}><option value="">Não definido</option>{users.filter(row => row.status === 'ativo' || row.id === project?.gestor_responsavel_id).map(row => <option key={row.id} value={row.id}>{row.nome}</option>)}</select></div>
      <div className="field"><label htmlFor="data_prevista_inicio">Início previsto</label><input id="data_prevista_inicio" name="data_prevista_inicio" type="date" defaultValue={inputDay(project?.data_prevista_inicio)} /></div>
      <div className="field"><label htmlFor="data_prevista_final">Entrega prevista</label><input id="data_prevista_final" name="data_prevista_final" type="date" defaultValue={inputDay(project?.data_prevista_final)} /></div>
      <div className="field"><label htmlFor="data_contratual">Data contratual</label><input id="data_contratual" name="data_contratual" type="date" defaultValue={inputDay(project?.data_contratual)} /></div>
      <div className="field"><label htmlFor="data_renegociada">Data renegociada</label><input id="data_renegociada" name="data_renegociada" type="date" defaultValue={inputDay(project?.data_renegociada)} /></div>
      <div className="field"><label htmlFor="contato">Contato</label><input id="contato" name="contato" defaultValue={project?.contato || ''} maxLength={500} /></div>
      <div className="field"><label htmlFor="proprietario">Proprietário</label><input id="proprietario" name="proprietario" defaultValue={project?.proprietario || ''} maxLength={500} /></div>
      <div className="field span-all"><label htmlFor="escopo_abreviado">Escopo do serviço</label><textarea id="escopo_abreviado" name="escopo_abreviado" defaultValue={project?.escopo_abreviado || ''} maxLength={5000} /></div>
      <div className="field span-all"><label htmlFor="eventualidades">Eventualidades</label><textarea id="eventualidades" name="eventualidades" defaultValue={project?.eventualidades || ''} maxLength={10000} /></div>
      <div className="field span-all"><label htmlFor="replanejamento_motivo">Observação do replanejamento</label><textarea id="replanejamento_motivo" name="replanejamento_motivo" defaultValue={project?.replanejamento_motivo || ''} maxLength={5000} /></div>
    </div></fieldset>
    <div className="form-actions"><span className="form-note">Informe ao menos o número ou o nome do projeto.</span><button type="button" className="button secondary" disabled={save.busy} onClick={() => window.location.assign(project ? `/projetos/${project.id}` : '/projetos')}>Voltar</button><button className="button" disabled={save.busy}>{save.busy ? 'Salvando…' : save.uncertain ? 'Tentar confirmar envio' : <><Icon name="check" size={16} />Salvar projeto</>}</button></div>
  </form>;
}

export function CellEditor({ projectId, allocation, cells, forms, users }: { projectId: string; allocation?: WebRow; cells: WebRow[]; forms: WebRow[]; users: WebRow[] }) {
  const [open, setOpen] = useState(false); const [customForms, setCustomForms] = useState(!!allocation);
  const save = useSave(planCell, () => { window.location.assign(`/projetos/${projectId}?tab=planejamento`); });
  const submit = (form: HTMLFormElement) => {
    const data = new FormData(form); const changes: Record<string, unknown> = { bloqueada: data.get('bloqueada'), visibilidade: data.get('visibilidade') === 'on', motivo_bloqueio: nullable(data, 'motivo_bloqueio'), observacao: nullable(data, 'observacao'), responsavel_id: nullable(data, 'responsavel_id') };
    for (const key of ['data_inicio', 'data_limite']) if (!allocation || String(data.get(key) || '') !== inputDay(allocation[key])) changes[key] = day(data.get(key));
    const hours = data.get('horas_previstas'); changes.horas_previstas = hours ? Number(hours) : null;
    if (allocation || data.get('custom_forms') === 'on') changes.forms_ids = data.getAll('forms_ids').map(String);
    void save.submit({ projeto_id: projectId, celula_id: allocation?.celula_id || String(data.get('celula_id')), expected_updated_at: allocation?.updated_at ?? null, changes });
  };
  if (!open) return <button className={`button small ${allocation ? 'secondary' : ''}`} onClick={() => setOpen(true)}><Icon name={allocation ? 'edit' : 'plus'} size={14} />{allocation ? 'Planejar' : 'Alocar célula'}</button>;
  return <div className="cell-editor" style={{ border: '1px solid #e8ebf0', background: '#fff', borderRadius: 8, padding: 23, margin: '18px 0' }}><h3 style={{ fontSize: 15, marginBottom: 20 }}>{allocation ? cells.find(cell => cell.id === allocation.celula_id)?.nome : 'Alocar célula no projeto'}</h3><form onSubmit={event => { event.preventDefault(); submit(event.currentTarget); }}>
    {save.error && <div role="alert" className="notice error">{save.error}</div>}<fieldset disabled={save.busy || save.uncertain} style={{ border: 0, margin: 0, padding: 0 }}><div className="form-grid">
      {!allocation && <div className="field span-all"><label htmlFor="new_cell">Célula *</label><select id="new_cell" name="celula_id" required><option value="">Selecione a célula</option>{cells.map(cell => <option key={cell.id} value={cell.id}>{cell.nome}</option>)}</select></div>}
      <div className="field"><label>Início previsto<input aria-label="Início previsto da célula" type="date" name="data_inicio" defaultValue={inputDay(allocation?.data_inicio)} /></label></div>
      <div className="field"><label>Prazo da célula<input aria-label="Prazo da célula" type="date" name="data_limite" defaultValue={inputDay(allocation?.data_limite)} /></label></div>
      <div className="field"><label>Responsável<select aria-label="Responsável da célula" name="responsavel_id" defaultValue={allocation?.responsavel_id || ''}><option value="">Não definido</option>{users.filter(user => user.status === 'ativo' || user.id === allocation?.responsavel_id).map(user => <option key={user.id} value={user.id}>{user.nome}</option>)}</select></label></div>
      <div className="field"><label>Horas previstas<input aria-label="Horas previstas" type="number" name="horas_previstas" min="0" max="1000000" step="0.01" defaultValue={allocation?.horas_previstas ?? ''} /></label></div>
      <div className="field"><label>Bloqueio de execução<select aria-label="Bloqueio de execução" name="bloqueada" defaultValue={allocation?.bloqueada || 'n_o'}><option value="n_o">Sem bloqueio</option><option value="sim">Bloqueada</option></select></label></div>
      <div className="field"><label>Motivo do bloqueio<input aria-label="Motivo do bloqueio" name="motivo_bloqueio" maxLength={5000} defaultValue={allocation?.motivo_bloqueio || ''} /></label></div>
      <label className="check-label span-all"><input type="checkbox" name="visibilidade" defaultChecked={allocation ? allocation.visibilidade : true} />Disponibilizar esta célula no aplicativo dos operadores autorizados</label>
      <div className="field span-all"><label>Observação<textarea aria-label="Observação do planejamento" name="observacao" maxLength={10000} defaultValue={allocation?.observacao || ''} /></label></div>
      <div className="span-all"><p className="field-label">Formulários da célula</p>{!allocation && <label className="check-label" style={{ marginBottom: 15 }}><input type="checkbox" name="custom_forms" checked={customForms} onChange={event => setCustomForms(event.target.checked)} />Definir formulários manualmente</label>}{customForms ? <div style={{ display: 'grid', gap: 10, maxHeight: 240, overflow: 'auto' }}>{forms.map(form => <label className="check-label" key={form.id}><input type="checkbox" name="forms_ids" value={form.id} defaultChecked={allocation?.forms_ids?.includes(form.id)} />{form.titulo}</label>)}</div> : <p className="form-note">Os formulários, fotos obrigatórias e aprovações serão copiados do roteiro cadastrado para o tipo de equipamento.</p>}</div>
    </div></fieldset><div className="form-actions"><button className="button secondary" type="button" disabled={save.busy} onClick={() => setOpen(false)}>Cancelar</button><button className="button" disabled={save.busy}>{save.busy ? 'Salvando…' : save.uncertain ? 'Tentar confirmar envio' : 'Salvar planejamento'}</button></div>
  </form></div>;
}

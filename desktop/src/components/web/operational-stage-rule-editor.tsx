'use client';

import { useEffect, useRef, useState } from 'react';
import { manageStageRules } from '@/server/web/operational-stage-rule-actions';
import type { ManageStageRulesInput } from '@/server/web/operational-stage-rule-policy';
import type { OperationalStageRulePerson, OperationalStageRuleSnapshot } from '@/server/web/operational-stage-rule-data';
import { canManageStageRules, emptyStageRuleConfig, stageRuleConfig, stageRuleConfigChanged, stageRuleDestinationChanged, stageRulePage, stageRulePeople, stageRulePersonLabel, stageRuleRequest, type StageRuleConfig, type StageRuleMode } from './operational-stage-rule-model';
import { EngineeringSaveNotice, useEngineeringSave } from './engineering-save';
import { projectRouteDestination } from './project-route-model';
import { Empty, Status, display } from './ui';
import { Icon } from './icons';
import s from './operational-stage-rule.module.css';

export function OperationalStageRuleEditor({ snapshot, canManage, destination }: {
  snapshot: OperationalStageRuleSnapshot; canManage: boolean; destination: string;
}) {
  const [mode, setMode] = useState<StageRuleMode | null>(null), [config, setConfig] = useState<StageRuleConfig>(emptyStageRuleConfig);
  const [confirmed, setConfirmed] = useState(false), [saved, setSaved] = useState(false), [retired, setRetired] = useState(false), [page, setPage] = useState(1);
  const initial = useRef(''), leaving = useRef(false), formHeading = useRef<HTMLHeadingElement>(null);
  const target = projectRouteDestination(destination, snapshot.project.id);
  const save = useEngineeringSave<ManageStageRulesInput>(async input => {
    const result = await manageStageRules(input); if (result.ok) { leaving.current = true; setSaved(true); } return result;
  }, target);
  const editable = canManageStageRules(snapshot, canManage), locked = save.locked || saved;
  const current = mode && mode.action !== 'create' ? snapshot.rules.find(rule => rule.id === mode.ruleId) : undefined;
  const configuring = mode?.action === 'create' || mode?.action === 'replace';
  const dirty = mode !== null && (JSON.stringify(config) !== initial.current || confirmed);
  const activeCount = snapshot.rules.filter(rule => rule.ativo).length, retiredCount = snapshot.rules.length - activeCount;
  const shown = stageRulePage(snapshot.rules, retired, page);
  const people = [...new Map([...snapshot.eligible_users, ...snapshot.rules.flatMap(rule => [...rule.approvers, ...rule.return_approvers])].map(person => [person.id, person])).values()];
  const names = (ids: readonly string[]) => ids.map(id => { const person = people.find(candidate => candidate.id === id); return person ? stageRulePersonLabel(person, people) : 'Referência não disponível'; }).join(', ') || 'Não definidos';
  const title = (status: string | null) => snapshot.statuses.find(item => item.key === status)?.label || display(status);
  const draftDestination = snapshot.destinations.find(item => item.celula_id === config.celula_destino_id);
  useEffect(() => { if (mode) formHeading.current?.focus(); }, [mode]);
  useEffect(() => {
    if (!dirty && !save.busy && !save.uncertain) return;
    const unload = (event: BeforeUnloadEvent) => { if (!leaving.current) { event.preventDefault(); event.returnValue = ''; } };
    const navigate = (event: MouseEvent) => {
      if (leaving.current || event.defaultPrevented || !(event.target instanceof Element)) return;
      const link = event.target.closest('a[href]'); if (!link || link.getAttribute('target') === '_blank') return;
      if (!window.confirm(save.uncertain ? 'A alteração da regra ainda não foi confirmada. Sair desta tela?' : 'Há alterações de regra não salvas. Sair sem salvar?')) { event.preventDefault(); event.stopPropagation(); }
      else leaving.current = true;
    };
    window.addEventListener('beforeunload', unload); document.addEventListener('click', navigate, true);
    return () => { window.removeEventListener('beforeunload', unload); document.removeEventListener('click', navigate, true); };
  }, [dirty, save.busy, save.uncertain]);
  function open(action: StageRuleMode['action'], ruleId?: string) {
    if (!editable || locked || mode) return;
    const rule = snapshot.rules.find(item => item.id === ruleId);
    if (action === 'create' && snapshot.total >= 1000 || action !== 'create' && (!rule || !(action === 'replace' ? rule.can_edit : action === 'retire' ? rule.can_retire : rule.can_restore))) return;
    const next: StageRuleMode = action === 'create' ? { action, id: crypto.randomUUID() } : action === 'replace'
      ? { action, ruleId: rule!.id, replacementId: crypto.randomUUID() } : { action, ruleId: rule!.id };
    const fields = action === 'replace' ? stageRuleConfig(rule!) : emptyStageRuleConfig();
    initial.current = JSON.stringify(fields); setConfig(fields); setMode(next); setConfirmed(false); save.setError('');
  }
  function cancel() { if (save.busy || save.uncertain) return; setMode(null); setConfirmed(false); save.setError(''); }
  function change(patch: Partial<StageRuleConfig>) { setConfig(fields => ({ ...fields, ...patch })); setConfirmed(false); }
  function submit() {
    if (save.uncertain) { save.retry(); return; }
    if (!mode || !editable || locked) return;
    try { void save.send(stageRuleRequest(snapshot, mode, config, confirmed, crypto.randomUUID())); }
    catch (error) { save.setError(error instanceof Error ? error.message : 'Confira a configuração da regra.'); }
  }
  function checks(label: string, cellId: string, field: 'aprovadores_ids' | 'aprovadores_retorno_ids') {
    const eligible = stageRulePeople(snapshot, cellId), selected = config[field], unavailable = selected.filter(id => !eligible.some(person => person.id === id));
    return <fieldset className={s.checks}><legend>{label}</legend>
      {eligible.map(person => <label key={person.id}><input type="checkbox" aria-label={`${label}: ${stageRulePersonLabel(person, eligible)}`} checked={selected.includes(person.id)} disabled={locked || selected.length >= 100 && !selected.includes(person.id)}
        onChange={event => change({ [field]: event.target.checked ? [...selected, person.id] : selected.filter(id => id !== person.id) })} /><span>{stageRulePersonLabel(person, eligible)}</span></label>)}
      {unavailable.map(id => <label key={id}><input type="checkbox" aria-label={`Remover seleção sem vínculo: ${names([id])}`} checked disabled={locked}
        onChange={() => change({ [field]: selected.filter(value => value !== id) })} /><span>{names([id])}<small>Sem vínculo elegível nesta célula. Desmarque para substituir a configuração.</small></span></label>)}
      {!eligible.length && <p>Nenhuma identidade ativa vinculada a esta célula.</p>}<small>Selecione entre 1 e 100 identidades.</small>
    </fieldset>;
  }
  if (!snapshot.complete || !snapshot.allocations_complete) return <Empty title="Este projeto excede o limite de configuração de etapas" detail="O conjunto completo precisa estar disponível para alterar regras. A consulta das decisões permanece disponível abaixo." icon="check" />;
  return <>
    <div className={s.toolbar}><p>As regras definem quando liberar o destino. Editar cria uma substituta e preserva a configuração anterior.</p>
      {canManage && <button type="button" className="button secondary" disabled={!editable || locked || !!mode || snapshot.total >= 1000} onClick={() => open('create')}><Icon name="plus" size={15} />Adicionar regra</button>}
    </div>
    <div className={s.notice}><EngineeringSaveNotice state={{ ...save, stale: false }} reload={target} />
      {save.stale && <p className="notice">As regras, o projeto ou os vínculos de aprovadores foram alterados. <a className="text-link" href={target} onClick={() => { leaving.current = true; }}>Recarregar regras da célula</a> antes de editar novamente.</p>}
      {save.busy && <p className="notice" role="status">Salvando alteração da regra…</p>}{saved && <p className="notice success" role="status">Alteração confirmada. Atualizando as regras…</p>}
      {canManage && (!snapshot.eligible_complete || !snapshot.memberships_complete) && <p className="notice">Os vínculos de aprovadores excedem o limite desta tela. As regras permanecem disponíveis para consulta.</p>}
      {canManage && snapshot.total >= 1000 && <p className="notice">O projeto atingiu o limite de versões de regras nesta tela. Novas regras e substituições estão bloqueadas; retirada e restauração seguem as condições de cada regra.</p>}
      {(snapshot.project.closed || snapshot.allocation.status === 'n_a') && <p className="notice">O projeto está encerrado ou a célula não é aplicável. As regras permanecem disponíveis para consulta.</p>}
    </div>
    {mode && <form className={s.form} onSubmit={event => { event.preventDefault(); submit(); }}>
      <h3 tabIndex={-1} ref={formHeading}>{mode.action === 'create' ? 'Nova regra de liberação' : mode.action === 'replace' ? 'Substituir configuração da regra' : mode.action === 'retire' ? 'Retirar regra do planejamento' : 'Restaurar regra original'}</h3>
      <fieldset className={s.fieldSet} disabled={locked}>
        {configuring ? <>
          {mode.action === 'replace' && <p>A configuração anterior ficará preservada nas retiradas. A substituta usará somente os aprovadores das listas selecionadas abaixo.{current?.aprovador_id && <> Aprovador individual legado: <strong>{names([current.aprovador_id])}</strong>.</>}</p>}
          <div className={s.grid}><div className="field"><label htmlFor="operational-rule-destination">Célula de destino *</label><select id="operational-rule-destination" value={config.celula_destino_id} onChange={event => { setConfig(fields => stageRuleDestinationChanged(fields, event.target.value)); setConfirmed(false); }}>
            <option value="">Selecione o destino</option>{config.celula_destino_id && !snapshot.destinations.some(item => item.celula_id === config.celula_destino_id) && <option value={config.celula_destino_id} disabled>Destino legado indisponível</option>}
            {snapshot.destinations.map(item => <option key={item.allocation_id} value={item.celula_id} disabled={!item.can_select}>{item.nome || 'Célula não disponível'}{!item.can_select ? ` · ${item.reason || 'Indisponível'}` : ''}</option>)}
          </select></div><div className="field"><label htmlFor="operational-rule-status">Status para liberação *</label><select id="operational-rule-status" value={config.status_cel_proj} onChange={event => change({ status_cel_proj: event.target.value })}>
            <option value="">Selecione o status</option>{config.status_cel_proj && !snapshot.statuses.some(item => item.key === config.status_cel_proj) && <option value={config.status_cel_proj} disabled>Status legado indisponível</option>}
            {snapshot.statuses.map(item => <option key={item.key} value={item.key}>{item.label}</option>)}
          </select></div></div>
          <label className="check-label"><input type="checkbox" checked={config.bloquear_avanco_sem_aprov} onChange={event => change({ bloquear_avanco_sem_aprov: event.target.checked })} />Aguardar todas as aprovações bloqueadoras antes de liberar o destino</label>
          <div className={s.grid}>{checks('Aprovadores na origem', snapshot.allocation.celula_id, 'aprovadores_ids')}{config.celula_destino_id ? checks('Aprovadores de retorno no destino', config.celula_destino_id, 'aprovadores_retorno_ids') : <p>Escolha o destino para selecionar os aprovadores do retorno.</p>}</div>
          <dl className={s.summary}><div><dt>Destino selecionado</dt><dd>{draftDestination?.nome || 'Não definido'}</dd></div><div><dt>Status para liberação</dt><dd>{title(config.status_cel_proj)}</dd></div><div><dt>Aprovadores na origem</dt><dd>{names(config.aprovadores_ids)}</dd></div><div><dt>Aprovadores de retorno</dt><dd>{names(config.aprovadores_retorno_ids)}</dd></div></dl>
        </> : <><p><strong>{title(current?.status_cel_proj ?? null)}</strong> · destino {current?.celula_destino_nome || 'não definido'}</p>
          <p>{mode.action === 'retire' ? 'A regra deixará de participar do planejamento. Sua configuração e os envios offline pendentes permanecerão preservados. A restauração deste mesmo registro dependerá das condições do projeto; quando impedida, o envio precisará de reconciliação.' : 'A regra voltará a usar sua configuração original e o mesmo identificador, permitindo retomar um envio offline pendente. Regras sucessoras ativas precisam ser retiradas primeiro.'}</p></>}
        {mode.action !== 'create' && <label className="check-label"><input type="checkbox" checked={confirmed} onChange={event => setConfirmed(event.target.checked)} />{mode.action === 'replace' ? 'Confirmo a substituição desta regra, preservando a configuração anterior.' : mode.action === 'retire' ? 'Confirmo a retirada desta regra.' : 'Confirmo a restauração da regra original.'}</label>}
      </fieldset>
      <div className={s.actions}><button type="button" className="button secondary" disabled={save.busy || save.uncertain} onClick={cancel}>Cancelar alteração</button>
        <button type="submit" className="button" disabled={save.busy || save.stale || save.unauthorized || saved || (!save.uncertain && (mode.action !== 'create' && !confirmed || mode.action === 'replace' && !!current && !stageRuleConfigChanged(current, config)))}>{save.busy ? 'Salvando…' : save.uncertain ? 'Tentar confirmar envio' : mode.action === 'create' ? 'Criar regra' : mode.action === 'replace' ? 'Confirmar substituição' : mode.action === 'retire' ? 'Confirmar retirada' : 'Confirmar restauração'}</button>
      </div>
    </form>}
    <div className={s.tabs} aria-label="Situação das regras"><button type="button" aria-pressed={!retired} disabled={locked || !!mode} onClick={() => { setRetired(false); setPage(1); }}>Em uso ({activeCount})</button><button type="button" aria-pressed={retired} disabled={locked || !!mode} onClick={() => { setRetired(true); setPage(1); }}>Retiradas ({retiredCount})</button></div>
    {shown.rows.length ? <div className={s.list}>{shown.rows.map(rule => <article className={s.item} key={rule.id} data-operational-stage-rule={rule.id}>
      <div className={s.heading}><div><h3>{rule.status_cel_proj === 'retornado' ? 'Regra de retorno' : 'Regra de liberação'} · {title(rule.status_cel_proj)}</h3><p>Destino: {rule.celula_destino_nome || 'Não definido'}</p></div><div className={s.badges}><Status value={rule.status ?? 'nulo'} />{!rule.ativo && <Status value="inativo" label="Retirada" />}{rule.used && <Status value="ativo" label="Com uso registrado" />}</div></div>
      <dl className={s.summary}><div><dt>Aprovadores na origem</dt><dd>{names(rule.aprovadores_ids)}</dd></div><div><dt>Aprovadores de retorno</dt><dd>{names(rule.aprovadores_retorno_ids)}</dd></div><div><dt>Aguardar aprovações bloqueadoras</dt><dd>{rule.bloquear_avanco_sem_aprov ? 'Sim' : 'Não'}</dd></div>{rule.aprovador_id && <div><dt>Aprovador individual legado</dt><dd>{names([rule.aprovador_id])}</dd></div>}</dl>
      {rule.supersedes_id && <p className={s.note}>Esta regra substitui uma configuração anterior, preservada nas retiradas.</p>}
      {rule.status_cel_proj === 'retornado' && <p className={s.note}>Regra de retorno gerada pela operação. Sua configuração permanece preservada.</p>}
      {(rule.history_ambiguous || rule.pair_ambiguous && !rule.managed_birth) && <p className={s.note}>O histórico ou o vínculo de retorno não permite uma alteração segura desta regra.</p>}
      {rule.related_return_ids.length > 0 && <p className={s.note}>{rule.managed_birth ? 'Há retornos anteriores deste trajeto; eles serão preservados.' : `Há ${rule.related_return_ids.length} regras de retorno relacionadas. Esta configuração permanece em consulta.`}</p>}
      {rule.action_reason && <p className={s.note}>{rule.action_reason}</p>}
      <div className={s.controls}><a className="text-link" href={`/aprovacoes/${rule.id}`}>Consultar etapa e histórico<Icon name="arrow" size={14} /></a>
        {editable && rule.can_edit && <button type="button" className="button small secondary" aria-label={`Editar regra de ${title(rule.status_cel_proj)} para ${rule.celula_destino_nome || 'destino não definido'}`} disabled={locked || !!mode} onClick={() => open('replace', rule.id)}><Icon name="edit" size={14} />Editar regra</button>}
        {editable && rule.can_retire && <button type="button" className="button small secondary" aria-label={`Retirar regra de ${title(rule.status_cel_proj)} para ${rule.celula_destino_nome || 'destino não definido'}`} disabled={locked || !!mode} onClick={() => open('retire', rule.id)}>Retirar regra</button>}
        {editable && rule.can_restore && <button type="button" className="button small secondary" aria-label={`Restaurar regra de ${title(rule.status_cel_proj)} para ${rule.celula_destino_nome || 'destino não definido'}`} disabled={locked || !!mode} onClick={() => open('restore', rule.id)}>Restaurar regra</button>}
      </div>
    </article>)}</div> : <Empty title={retired ? 'Nenhuma regra retirada' : 'Nenhuma regra de etapa nesta célula'} detail={retired ? 'As configurações retiradas permanecem preservadas para consulta e recuperação.' : 'O planejamento pode definir as condições para liberar uma célula de destino do projeto.'} icon="check" />}
    <div className={s.pagination}><span>{shown.total} regras · página {shown.page} de {shown.pages}</span><div><button type="button" className="button small secondary" disabled={locked || !!mode || shown.page <= 1} onClick={() => setPage(shown.page - 1)}>Anterior</button><button type="button" className="button small secondary" disabled={locked || !!mode || shown.page >= shown.pages} onClick={() => setPage(shown.page + 1)}>Próxima</button></div></div>
  </>;
}

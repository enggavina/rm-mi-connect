import type { ProjectEquipmentSnapshot } from '@/server/web/project-equipment-policy';
import { ProjectEquipmentEditor } from './project-equipment-editor';
import { EngineeringReloadLink } from './engineering-save';
import { equipmentDisplayValue, equipmentFieldGroups, projectEquipmentMatches } from './project-equipment-model';
import s from './project-equipment.module.css';

export function ProjectEquipmentPanel({ snapshot: suppliedSnapshot, project, canManage }: {
  snapshot: ProjectEquipmentSnapshot | null;
  project: { id: string; updated_at: string; equipamento_id?: string | null; tipo_equipamento_id?: string | null; status_pcp?: string | null; data_real_de_entrega?: string | null };
  canManage: boolean;
}) {
  const snapshot = suppliedSnapshot?.project.id === project.id ? suppliedSnapshot : null;
  const current = !!snapshot && projectEquipmentMatches(snapshot, project), linked = snapshot?.binding_state === 'linked' && !!snapshot.equipment;
  const editable = current && linked && canManage && snapshot.can_edit && !snapshot.project.closed;
  return <section className="panel" id="dados-equipamento" data-project-equipment-panel>
    <div className="panel-header"><div><h2>Dados do equipamento</h2><p>Identificação, dados elétricos e construção</p></div></div>
    {!snapshot ? <div className={s.body}><p className="notice" role="status">Não foi possível conferir os dados do equipamento agora. <EngineeringReloadLink href={`/projetos/${project.id}?tab=informacoes#dados-equipamento`}>Recarregar dados</EngineeringReloadLink></p></div>
      : !linked ? <div className={s.body}><p className="notice" role="status">{snapshot.reason || 'O vínculo do equipamento precisa ser conferido antes da edição. Os dados do projeto permanecem disponíveis para consulta.'}</p></div>
        : <><div className={s.body}>
          {!current && <p className="notice" role="status">O projeto mudou durante a consulta. <EngineeringReloadLink href={`/projetos/${project.id}?tab=informacoes#dados-equipamento`}>Recarregar dados</EngineeringReloadLink> antes de editar o equipamento.</p>}
          {snapshot.type_mismatch && <p className="notice" role="status">O tipo cadastrado no equipamento difere do projeto. Confira os cadastros; os dados técnicos podem ser consultados sem alterar essa classificação.</p>}
          <div className={s.groups}>{equipmentFieldGroups.map(group => <section key={group.id} className={s.group} aria-label={group.title}><h3>{group.title}</h3><dl className={s.values}>{group.fields.map(field => <div key={field.key} className={'multiline' in field ? s.spanAll : undefined}><dt>{field.label}</dt><dd>{equipmentDisplayValue(field.key, snapshot.equipment?.[field.key])}</dd></div>)}</dl></section>)}</div>
        </div>
          {editable ? <ProjectEquipmentEditor key={snapshot.context_version} snapshot={snapshot} /> : <div className={s.readonly}><p className="form-note">{snapshot.project.closed ? 'Projeto encerrado. Os dados técnicos permanecem disponíveis para consulta.' : current ? snapshot.reason || 'Dados técnicos disponíveis para consulta conforme seu perfil de acesso.' : 'A edição ficará disponível após conferir a versão atual do projeto.'}</p></div>}
        </>}
  </section>;
}

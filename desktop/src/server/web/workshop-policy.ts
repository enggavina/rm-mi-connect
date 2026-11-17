import { z } from 'zod';
import type { WorkshopActivity, WorkshopOrder, WorkshopSnapshot, ModelKind } from '@/components/workshop/domain/types';
import { calendarDay, isValidDateValue } from '@/components/workshop/domain/metrics';
import { uuid } from './policy';

export const WORKSHOP_MAX_PROJECTS = 2000;
export const WORKSHOP_MAX_ALLOCATIONS = 20_000;
export const WORKSHOP_MAX_CELLS = 2000;
export const WORKSHOP_MAX_BYTES = 10 * 1024 * 1024;

export const activeWorkshopStatuses = [
  'equipamento_inspecionado', 'executando', 'aguardando_aprova__o', 'revis_o_comercial', 'revis_o_comercial0',
  'susponso__hold_', 'equipamento_em_inspe__o', 'sem_previs_o', 'investiga__o_de_garantia', 'executando_com_garantia',
] as const;
const projectLabels: Record<string, string> = {
  equipamento_inspecionado: 'Equipamento inspecionado', executando: 'Executando', aguardando_aprova__o: 'Aguardando aprovação',
  revis_o_comercial: 'Revisão comercial', revis_o_comercial0: 'Revisão comercial', susponso__hold_: 'Suspenso (HOLD)',
  equipamento_em_inspe__o: 'Equipamento em inspeção', sem_previs_o: 'Sem previsão',
  investiga__o_de_garantia: 'Investigação de garantia', executando_com_garantia: 'Executando com garantia',
};
const allocationLabels: Record<string, string> = {
  pendente: 'Pendente', retornado: 'Retornado', liberado_para_ensaios_parciais: 'Liberado para ensaios parciais',
  liberado_para_impregna__o: 'Liberado para impregnação', liberado_para_montagem: 'Liberado para montagem',
  para_execu__o: 'Para execução', em_dia: 'Executando', finalizado: 'Finalizado', atrasado: 'Atrasado', n_a: 'N/A',
  aguardando_coleta: 'Aguardando coleta', coletado: 'Coletado',
};
const activeStatuses = new Set<string>(activeWorkshopStatuses);
const text = z.string().nullable();
const timestamp = z.string().datetime({ offset: true }).refine(isValidDateValue, 'Data inválida');
const numeric = z.string().regex(/^-?\d+(?:\.\d+)?$/).nullable();
export const rawWorkshopSnapshotSchema = z.object({
  as_of: timestamp,
  project_count: z.number().int().min(0).max(WORKSHOP_MAX_PROJECTS),
  allocation_count: z.number().int().min(0).max(WORKSHOP_MAX_ALLOCATIONS),
  cell_count: z.number().int().min(0).max(WORKSHOP_MAX_CELLS),
  projects: z.array(z.object({
    id: uuid, numero: text, nome: text, descricao_equipamento: text, status_pcp: text,
    chegada_do_equipamento: timestamp.nullable(), data_real_de_entrega: timestamp.nullable(),
    data_prevista_final: timestamp.nullable(), data_contratual: timestamp.nullable(), data_renegociada: timestamp.nullable(),
    cliente_nome: text, gestor_nome: text, equipamento_tipo: text, equipamento_descricao: text,
    fabricante: text, modelo: text, potencia: text, rotacao: text, numero_serie: text, equipment_binding: z.boolean(),
  })).max(WORKSHOP_MAX_PROJECTS),
  allocations: z.array(z.object({
    id: uuid, projeto_id: uuid, celula_id: uuid, status: text, bloqueada: z.enum(['sim', 'n_o']).nullable(),
    motivo_bloqueio: text, data_inicio: timestamp.nullable(), data_limite: timestamp.nullable(), data_fim_real: timestamp.nullable(),
    responsavel_nome: text, prioridade: text, horas_previstas: numeric, horas_realizadas: numeric,
    visibilidade: z.boolean(), indice: z.number().int().nullable(),
  })).max(WORKSHOP_MAX_ALLOCATIONS),
  cells: z.array(z.object({ id: uuid, nome: text, ordem: z.number().int().nullable() })).max(WORKSHOP_MAX_CELLS),
});
export type RawWorkshopSnapshot = z.infer<typeof rawWorkshopSnapshotSchema>;

const normalize = (value: string) => value.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase().trim().replace(/\s+/g, ' ');
const knownModels = new Map<string, ModelKind>([
  ['gerador', 'generator'], ['transformador', 'transformer'], ['drive - inversor de frequencia', 'drive'],
  ...[
    'motor - ac-bt - ex-d weg', 'motor - ac-bt - standard', 'motor - ac-bt - ex- e(eb) -n(ec) -t',
    'motor - ac-bt - ex-de weg', 'motor - ac-bt - ex-d - norma', 'motor - ac-bt - ex-de - norma',
    'motor eletrico de media tensao corrente alternada', 'motor eletrico de media tensao corrente continua',
    'motor fast - ac-bt - standard', 'motores armazenados',
  ].map(name => [name, 'motor'] as [string, ModelKind]),
]);
const present = (value: string | null) => value?.trim() || null;
const key = (id: string) => id.toLowerCase();
const closed = (activity: WorkshopActivity) => activity.status === 'Finalizado' || activity.status === 'N/A' || activity.completedAt !== null;
const unavailable = () => new Error('Não foi possível confirmar os dados completos do gêmeo digital. Atualize a consulta.');
function unitNumber(value: string | null, unit: 'kW' | 'rpm'): number | null {
  if (value === null) return null;
  const match = value.trim().match(new RegExp(`^([0-9]+(?:[.,][0-9]+)?)\\s*${unit}$`, 'i'));
  if (!match) return null;
  const parsed = Number(match[1].replace(',', '.'));
  return Number.isFinite(parsed) && parsed > 0 ? parsed : null;
}

/** A complete operational snapshot is validated before deriving any metric or
 * visual slot. The mapper never converts a partial read into an empty workshop. */
export function mapWorkshopSnapshot(input: unknown): WorkshopSnapshot {
  try {
    if (new TextEncoder().encode(JSON.stringify(input)).length > WORKSHOP_MAX_BYTES) throw unavailable();
  } catch { throw unavailable(); }
  const parsed = rawWorkshopSnapshotSchema.safeParse(input);
  if (!parsed.success) throw unavailable();
  const data = parsed.data;
  if (data.projects.length !== data.project_count || data.allocations.length !== data.allocation_count || data.cells.length !== data.cell_count) throw unavailable();
  const projects = new Set(data.projects.map(project => key(project.id)));
  const cells = new Map(data.cells.map(cell => [key(cell.id), cell]));
  if (projects.size !== data.projects.length || cells.size !== data.cells.length
    || new Set(data.allocations.map(allocation => key(allocation.id))).size !== data.allocations.length) throw unavailable();
  const referenceDay = calendarDay(data.as_of)!;
  if (data.projects.some(project => !activeStatuses.has(project.status_pcp ?? '') || project.data_real_de_entrega !== null
    || !project.chegada_do_equipamento || calendarDay(project.chegada_do_equipamento)! > referenceDay
    || !project.equipment_binding && [project.equipamento_descricao, project.fabricante, project.modelo, project.potencia, project.rotacao, project.numero_serie].some(value => value !== null))) throw unavailable();
  const byProject = new Map<string, RawWorkshopSnapshot['allocations']>();
  const pairs = new Set<string>();
  for (const allocation of data.allocations) {
    if (!projects.has(key(allocation.projeto_id)) || !cells.has(key(allocation.celula_id))) throw unavailable();
    const pair = `${key(allocation.projeto_id)}:${key(allocation.celula_id)}`;
    if (pairs.has(pair)) throw unavailable();
    pairs.add(pair);
    const siblings = byProject.get(key(allocation.projeto_id)) ?? [];
    siblings.push(allocation); byProject.set(key(allocation.projeto_id), siblings);
  }
  let genericModels = 0, closedBlocks = 0, unallocated = 0;
  const orders: WorkshopOrder[] = data.projects.map(project => {
    const activities: WorkshopActivity[] = [...(byProject.get(key(project.id)) ?? [])]
      .sort((a, b) => (a.indice ?? 1e9) - (b.indice ?? 1e9) || a.id.localeCompare(b.id))
      .map(allocation => ({ id: allocation.id, cellId: allocation.celula_id,
        name: present(cells.get(key(allocation.celula_id))!.nome),
        status: allocation.status === null ? null : allocationLabels[allocation.status] ?? allocation.status,
        blocked: allocation.bloqueada === 'sim' ? true : allocation.bloqueada === 'n_o' ? false : null,
        blockReason: present(allocation.motivo_bloqueio), startedAt: allocation.data_inicio, dueAt: allocation.data_limite,
        completedAt: allocation.data_fim_real, responsible: present(allocation.responsavel_nome),
      }));
    const current = activities.filter(activity => !closed(activity));
    const running = current.filter(activity => activity.status === 'Executando');
    const blocked = current.filter(activity => activity.blocked === true);
    closedBlocks += activities.filter(activity => closed(activity) && activity.blocked === true).length;
    const activeStageNames = [...new Set(running.map(activity => activity.name).filter((name): name is string => name !== null))];
    const equipmentType = present(project.equipamento_tipo), model = equipmentType ? knownModels.get(normalize(equipmentType)) : undefined;
    if (!model) genericModels++;
    if (!activities.length) unallocated++;
    return {
      id: project.id, code: present(project.numero) ?? 'Recebimento sem OS',
      equipment: present(project.descricao_equipamento) ?? present(project.equipamento_descricao)
        ?? ([present(project.fabricante), present(project.modelo)].filter(Boolean).join(' · ') || present(project.nome) || 'Equipamento sem descrição'),
      client: present(project.cliente_nome), stage: running.length === 1 ? running[0].name : running.length > 1 ? 'Múltiplas etapas em execução' : null,
      status: projectLabels[project.status_pcp!], responsible: present(project.gestor_nome),
      enteredAt: project.chegada_do_equipamento, dueAt: project.data_contratual, completedAt: project.data_real_de_entrega,
      blockReason: [...new Set(blocked.map(activity => activity.blockReason).filter(Boolean))].join(' · ') || null,
      blockDeclared: blocked.length ? true : current.length > 0 && current.every(activity => activity.blocked === false) ? false : null,
      priority: null, powerKw: unitNumber(project.potencia, 'kW'), rpm: unitNumber(project.rotacao, 'rpm'), serial: present(project.numero_serie),
      locationId: null, locationVerified: false, model: model ?? 'motor', equipmentType, modelVerified: !!model,
      sourceUrl: `/projetos/${project.id}`, history: [], activities, activeStageNames,
      dueSource: project.data_contratual ? 'contractual' : null, powerRaw: project.potencia, rpmRaw: project.rotacao,
    };
  });
  const warnings = [
    'Dados do Supabase EM, na mesma base da plataforma web e do aplicativo. A consulta é somente de leitura e considera projetos recebidos, ainda sem entrega e com status PCP operacional.',
    'O mapa representa o processo. A posição física dos equipamentos e a capacidade real de pessoas, bancadas e máquinas não estão cadastradas; recursos e animações da planta são ilustrativos.',
    'Somente células com status Executando e sem fim real geram uma etapa em execução. Para execução e pendências continuam em espera; um projeto pode executar em várias células.',
    'O prazo do projeto usa a data contratual. Datas previstas ou renegociadas não substituem silenciosamente esse compromisso; ausência de data contratual permanece sem prazo.',
  ];
  if (genericModels) warnings.push(`${genericModels} projeto(s) têm modelo 3D genérico por tipo ausente ou não suportado; a forma exibida não comprova o tipo do equipamento.`);
  if (closedBlocks) warnings.push(`${closedBlocks} célula(s) encerrada(s) possuem bloqueio histórico, preservado no detalhe e excluído do bloqueio atual.`);
  if (unallocated) warnings.push(`${unallocated} projeto(s) ainda não possuem alocação ativa de célula. Nenhuma etapa em execução foi inventada.`);
  return { schemaVersion: 1, source: 'supabase', fetchedAt: data.as_of, referenceAt: data.as_of, orders,
    cells: data.cells.map(cell => ({ id: cell.id, name: present(cell.nome) ?? 'Célula sem nome cadastrado', order: cell.ordem })), resources: [], warnings };
}

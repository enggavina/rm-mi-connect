import type { SupabaseClient } from '@supabase/supabase-js';
import { pageNumber, searchTerm, uuid } from './policy';

// Only explicit, public operational columns enter these DTOs. In particular,
// rm_users never uses select('*') or exposes Auth/credential metadata.
export type WebRow = { id: string; [key: string]: any };
export type WebPage = { rows: WebRow[]; total: number; page: number; pageSize: number };
export type ProjectFilters = { q?: string; status?: string; client?: string; cell?: string; page?: number | string };
export type PlanningFilters = { q?: string; status?: string; cell?: string; page?: number | string };
export type FormFilters = { q?: string; status?: string; page?: number | string };
export type CatalogKind = 'users' | 'cells' | 'types' | 'clients' | 'forms';
export const catalogKinds: CatalogKind[] = ['users', 'cells', 'types', 'clients', 'forms'];

const PROJECT = 'id,numero,nome,cliente_id,cliente_nome_exportacao,tipo_equipamento_id,equipamento_id,descricao_equipamento,contato,proprietario,escopo_abreviado,eventualidades,gestor_responsavel_id,status,status_pcp,nota_fiscal,arquivo_nota_fiscal_url,documento_proposta_url,chegada_do_equipamento,data_prevista_inicio,data_prevista_final,data_contratual,data_renegociada,data_real_de_entrega,replanejamento_motivo,created_at,updated_at';
const USER = 'id,nome,matricula,cargo,perfil,status,foto_url';
const CLIENT = 'id,codigo,nome,descricao';
const CELL = 'id,codigo,nome,indice,ordem';
const FORM = 'id,titulo,title,descricao,tipo,ativo,usa_aprovacao,updated_at';
const ALLOCATION = 'id,projeto_id,celula_id,numero_projeto,cliente_nome_export,tipo_equipamento_nome_export,status,bloqueada,motivo_bloqueio,motivo_atraso,observacao,visibilidade,prioridade,indice,posicao,horas_previstas,horas_realizadas,data_inicio,data_limite,data_fim_real,responsavel_id,forms_ids,updated_at';
const RECORD = 'id,projeto_id,numero_projeto_rm,celula_id,form_id,codigo,codigo_text,descricao,status,preenchido,revisado,parecer,data_conclusao,data_revisao,created_by_user_id,identidade_user_id,responsavel_user_id,avaliador_user_id,aprovadores_ids,user_revisao_id,created_at,updated_at';
const ANSWER = 'id,registro_formulario_id,questao_id,titulo_form,indice,enunciado,tag,tipo,dimensoes,resposta,itens,itens_questoes_ids,fotos_urls,assinatura_url,date_inicio,data_fim,hora,revisar,updated_at';
const QUESTION = 'id,form_id,indice,enunciado,subtitulo,tag,tipo,subtipo,dimensoes,obrigatorio';
const ITEM = 'id,form_id,questao_id,indice,descricao';
const PHOTO = 'id,projeto_id,celula_id,celula_projeto_id,categoria_foto,tipo_recebimento,identificador_foto_key,titulo,descricao,legenda,foto_url,numero,selecao_relatorio,created_at';
const DOCUMENT = 'id,projeto_id,registro_formulario_id,nome,tipo_documento,arquivo_url,ordem_compilacao,incluir_no_compilado,created_at,updated_at';
const ATTACHMENT = 'id,projeto_id,nome,descricao,arquivo_url,tipo_arquivo,created_at,updated_at';
const ACTIVE = 'status_pcp.not.in.(cancelado,finalizando_para_faturar),status_pcp.is.null';
const catalogs = {
  users: { table: 'rm_users', columns: USER, order: 'nome', search: 'nome,matricula' },
  cells: { table: 'rm_celulas', columns: CELL, order: 'nome', search: 'nome,codigo' },
  types: { table: 'rm_tipos_equipamento', columns: 'id,nome,sigla', order: 'nome', search: 'nome,sigla' },
  clients: { table: 'rm_clientes', columns: CLIENT, order: 'nome', search: 'nome,codigo' },
  forms: { table: 'rm_forms', columns: FORM, order: 'titulo', search: 'titulo,descricao' },
} as const;

function checked<T extends { error: { message: string } | null }>(result: T): T {
  if (result.error) throw new Error('Não foi possível consultar os dados. Tente novamente.');
  return result;
}
function ids(values: unknown[]): string[] { return [...new Set(values.filter((v): v is string => typeof v === 'string' && uuid.safeParse(v).success))]; }
function applySearch(query: any, value: unknown, columns: string[], referencedTable?: string) {
  const term = searchTerm(value);
  return term ? query.or(columns.map(column => `${column}.ilike.%${term}%`).join(','), referencedTable ? { referencedTable } : undefined) : query;
}
async function page(query: any, number: unknown, pageSize: number): Promise<WebPage> {
  const current = pageNumber(number);
  const result = checked(await query.range((current - 1) * pageSize, current * pageSize - 1)) as any;
  return { rows: result.data || [], total: result.count ?? 0, page: current, pageSize };
}

/** Injectable RLS client makes pagination and scope testable without Auth secrets. */
export function createWebData(client: SupabaseClient) {
  async function all(table: string, columns: string, filter?: (query: any) => any, order = 'id'): Promise<WebRow[]> {
    const output: WebRow[] = [];
    for (let offset = 0; offset < 20_000; offset += 500) {
      let query: any = client.from(table).select(columns).order(order, { ascending: true }).order('id', { ascending: true });
      if (filter) query = filter(query);
      const result = checked(await query.range(offset, offset + 499)) as any;
      output.push(...(result.data || []));
      if (!result.data || result.data.length < 500) return output;
    }
    throw new Error('A consulta excedeu o limite desta tela. Restrinja os filtros.');
  }
  async function byIds(table: string, columns: string, values: unknown[]): Promise<WebRow[]> {
    const selected = ids(values), result: WebRow[] = [];
    for (let at = 0; at < selected.length; at += 100) result.push(...await all(table, columns, query => query.in('id', selected.slice(at, at + 100))));
    return result;
  }
  async function one(table: string, columns: string, id: string): Promise<WebRow | null> {
    if (!uuid.safeParse(id).success) return null;
    return (checked(await client.from(table).select(columns).eq('id', id).maybeSingle()) as any).data;
  }
  async function options(set: string): Promise<WebRow[]> {
    const result = checked(await client.from('rm_option_sets').select('option_key,bubble_display,sort_order').eq('option_set_key', set).order('sort_order'));
    return (result.data || []).map(row => ({ ...row, id: row.option_key }));
  }
  async function count(table: string, filter?: (query: any) => any): Promise<number> {
    let query: any = client.from(table).select('id', { count: 'exact', head: true });
    if (filter) query = filter(query);
    return (checked(await query) as any).count ?? 0;
  }
  async function getOverview() {
    const [projects, activeProjects, awaitingReview, overdueCells, reportCount, attachmentCount, recent, records, overdue] = await Promise.all([
      count('rm_projetos'), count('rm_projetos', q => q.is('data_real_de_entrega', null).or(ACTIVE)),
      count('rm_registros_formulario', q => q.eq('status', 'em_an_lise')),
      count('rm_celulas_projeto', q => q.lt('data_limite', new Date().toISOString()).neq('status', 'finalizado').eq('visibilidade', true)),
      count('rm_documentos'), count('rm_docs'),
      client.from('rm_projetos').select(PROJECT).order('updated_at', { ascending: false }).order('id').limit(8),
      client.from('rm_registros_formulario').select(RECORD).eq('status', 'em_an_lise').order('updated_at', { ascending: false }).order('id').limit(8),
      client.from('rm_celulas_projeto').select(ALLOCATION).lt('data_limite', new Date().toISOString()).neq('status', 'finalizado').eq('visibilidade', true).order('data_limite').order('id').limit(8),
    ]);
    const recentRows = (checked(recent) as any).data as WebRow[];
    const recentClients = await byIds('rm_clientes', CLIENT, recentRows.map(row => row.cliente_id));
    const recentProjects: WebRow[] = recentRows.map(row => ({ ...row, cliente_nome: recentClients.find(customer => customer.id === row.cliente_id)?.nome || row.cliente_nome_exportacao || null }));
    const recentRecords = (checked(records) as any).data as WebRow[];
    const tasks: WebRow[] = [
      ...recentRecords.map(row => ({ ...row, kind: 'review', title: `Avaliar formulário ${row.codigo_text || row.codigo || ''}`, href: `/formularios/${row.id}` })),
      ...((checked(overdue) as any).data as WebRow[]).map(row => ({ ...row, kind: 'overdue', title: `Prazo vencido · ${row.numero_projeto || 'Projeto'}`, href: `/projetos/${row.projeto_id}` })),
    ];
    return { counts: { projects, activeProjects, awaitingReview, overdueCells, documents: reportCount + attachmentCount }, recentProjects, recentRecords, tasks };
  }
  async function listProjects(filters: ProjectFilters = {}) {
    let query: any = client.from('rm_projetos').select(PROJECT + (filters.cell ? ',allocations:rm_celulas_projeto!inner(celula_id)' : ''), { count: 'exact' });
    query = applySearch(query, filters.q, ['numero', 'nome', 'cliente_nome_exportacao', 'descricao_equipamento']);
    if (filters.status) query = query.eq('status_pcp', filters.status);
    if (filters.client) query = query.eq('cliente_id', uuid.parse(filters.client));
    if (filters.cell) query = query.eq('allocations.celula_id', uuid.parse(filters.cell));
    const [result, clients, cells, statuses] = await Promise.all([
      page(query.order('updated_at', { ascending: false }).order('id'), filters.page, 25),
      all('rm_clientes', CLIENT, undefined, 'nome'), all('rm_celulas', CELL, undefined, 'nome'), options('status_pcp'),
    ]);
    const names = new Map(clients.map(row => [row.id, row.nome]));
    result.rows = result.rows.map(row => ({ ...row, cliente_nome: names.get(row.cliente_id) || row.cliente_nome_exportacao || null }));
    return { ...result, clients, cells, statuses };
  }
  async function getProject(id: string, filters: { photoPage?: number | string } = {}) {
    const project = await one('rm_projetos', PROJECT, id);
    if (!project) return null;
    const [customers, equipmentRows, allocations, cells, records, stages, comments, pictures, documents, attachments] = await Promise.all([
      byIds('rm_clientes', CLIENT, [project.cliente_id]),
      all('rm_equipamentos', 'id,projeto_id,tipo_equipamento_id,descricao,placa_motor,fabricante,modelo,numero_serie,potencia,tensao_estator,corrente_estator,rotacao,frequencia,classe_isolamento,grau_ip,forma,regime,peso,ligacao,certificado,norma,updated_at', q => q.eq('projeto_id', id)),
      all('rm_celulas_projeto', ALLOCATION, q => q.eq('projeto_id', id), 'posicao'), all('rm_celulas', CELL, undefined, 'indice'),
      all('rm_registros_formulario', RECORD, q => q.eq('projeto_id', id), 'created_at'),
      all('rm_aprovacoes_etapas', 'id,projeto_id,celula_projeto_id,celula_origem_id,celula_destino_id,status,status_cel_proj,aprovador_id,aprovado_por_id,data_aprovacao,updated_at', q => q.eq('projeto_id', id)),
      all('rm_comentarios', 'id,projeto_id,celula_id,cadastrado_por_id,evento,created_at', q => q.eq('projeto_id', id), 'created_at'),
      page(client.from('rm_fotos').select(PHOTO, { count: 'exact' }).eq('projeto_id', id).eq('lixeira', false).not('foto_url', 'is', null).order('numero').order('id'), filters.photoPage, 24),
      all('rm_documentos', DOCUMENT, q => q.eq('projeto_id', id), 'ordem_compilacao'), all('rm_docs', ATTACHMENT, q => q.eq('projeto_id', id), 'nome'),
    ]);
    const [forms, users] = await Promise.all([
      byIds('rm_forms', FORM, [...allocations.flatMap(row => row.forms_ids || []), ...records.map(row => row.form_id)]),
      byIds('rm_users', USER, [...records.flatMap(row => [row.identidade_user_id, row.created_by_user_id, row.responsavel_user_id, row.avaliador_user_id, row.user_revisao_id]), ...comments.map(row => row.cadastrado_por_id), ...stages.flatMap(row => [row.aprovador_id, row.aprovado_por_id]), ...allocations.map(row => row.responsavel_id)]),
    ]);
    return { project, client: customers[0] || null, equipment: equipmentRows.find(row => row.id === project.equipamento_id) || equipmentRows[0] || null,
      allocations, cells, forms, records, stages, comments, users, photos: pictures.rows, photoTotal: pictures.total, photoPage: pictures.page, photoPageSize: pictures.pageSize, documents, attachments };
  }
  async function getRecord(id: string) {
    const record = await one('rm_registros_formulario', RECORD, id);
    if (!record) return null;
    const [project, form, answers, questions, items, users] = await Promise.all([
      one('rm_projetos', PROJECT, record.projeto_id), one('rm_forms', FORM, record.form_id),
      all('rm_respostas', ANSWER, q => q.eq('registro_formulario_id', id), 'indice'),
      all('rm_questoes', QUESTION, q => q.eq('form_id', record.form_id), 'indice'),
      all('rm_itens_questoes', ITEM, q => q.eq('form_id', record.form_id), 'indice'),
      byIds('rm_users', USER, [record.identidade_user_id, record.created_by_user_id, record.responsavel_user_id, record.avaliador_user_id, record.user_revisao_id]),
    ]);
    return { record, project, form, answers, questions, items, users };
  }
  async function listPlanning(filters: PlanningFilters = {}) {
    let query: any = client.from('rm_celulas_projeto').select(`${ALLOCATION},project:rm_projetos!inner(id,numero,nome,status_pcp,data_real_de_entrega,cliente_nome_exportacao)`, { count: 'exact' });
    if (filters.cell) query = query.eq('celula_id', uuid.parse(filters.cell));
    if (filters.status) query = query.eq('status', filters.status);
    query = applySearch(query, filters.q, ['numero', 'nome', 'cliente_nome_exportacao'], 'project');
    const [result, projects, cells, statuses] = await Promise.all([
      page(query.order('posicao').order('id'), filters.page, 50),
      all('rm_projetos', 'id,numero,nome,status_pcp,data_real_de_entrega', undefined, 'numero'), all('rm_celulas', CELL, undefined, 'nome'), options('status_cel_proj'),
    ]);
    return { ...result, projects, cells, statuses };
  }
  async function listForms(filters: FormFilters = {}) {
    let query: any = client.from('rm_registros_formulario').select(RECORD, { count: 'exact' });
    if (filters.status) query = query.eq('status', filters.status);
    query = applySearch(query, filters.q, ['numero_projeto_rm', 'codigo_text', 'descricao']);
    const [result, forms, projects, statuses] = await Promise.all([
      page(query.order('updated_at', { ascending: false }).order('id'), filters.page, 25), all('rm_forms', FORM, undefined, 'titulo'),
      all('rm_projetos', 'id,numero,nome', undefined, 'numero'), options('status_registro0'),
    ]);
    return { ...result, forms, projects, statuses };
  }
  async function getCatalogs(filters: { kind?: string; q?: string; page?: number | string } = {}) {
    const kind: CatalogKind = catalogKinds.includes(filters.kind as CatalogKind) ? filters.kind as CatalogKind : 'clients';
    const catalog = catalogs[kind];
    let query: any = client.from(catalog.table).select(catalog.columns, { count: 'exact' });
    query = applySearch(query, filters.q, catalog.search.split(','));
    return { ...await page(query.order(catalog.order).order('id'), filters.page, 50), kind, kinds: catalogKinds };
  }
  return { getOverview, listProjects, getProject, getRecord, listPlanning, listForms, getCatalogs };
}

async function data() { const { requireWebUser } = await import('./auth'); return createWebData((await requireWebUser()).client); }
export async function getOverview() { return (await data()).getOverview(); }
export async function listProjects(filters: ProjectFilters = {}) { return (await data()).listProjects(filters); }
export async function getProject(id: string, filters: { photoPage?: number | string } = {}) { return (await data()).getProject(id, filters); }
export async function getRecord(id: string) { return (await data()).getRecord(id); }
export async function listPlanning(filters: PlanningFilters = {}) { return (await data()).listPlanning(filters); }
export async function listForms(filters: FormFilters = {}) { return (await data()).listForms(filters); }
export async function getCatalogs(filters: { kind?: string; q?: string; page?: number | string } = {}) { return (await data()).getCatalogs(filters); }

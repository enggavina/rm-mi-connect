export interface TemplateItem { id: string; indice: string; descricao: string; description: string | null }
export interface TemplateQuestion { id: string; indice: string; enunciado: string; title: string | null; subtitulo: string | null; tag: string | null; tipo: string; subtipo: string | null; dimensoes: string | null; obrigatorio: boolean; colaborador_filtro_perfil: string | null; items: TemplateItem[] }
export interface TemplateContent { titulo: string; descricao: string | null; title: string | null; description: string | null; tipo: string | null; questions: TemplateQuestion[] }
export interface TemplateDraft { id: string; kind: 'new' | 'copy' | 'version'; state: 'draft' | 'published'; family_id: string | null; source_form_id: string | null; source_version: number | null; content: TemplateContent; source_snapshot: { usa_aprovacao: boolean | null; has_cover: boolean; celulas_ids: string[]; equipes_ids: string[] }; created_at: string; updated_at: string; published_form_id: string | null }
export interface TemplateOption { option_key: string; bubble_display: string }
export interface TemplateChoices { formTypes: TemplateOption[]; questionTypes: TemplateOption[]; subtypes: TemplateOption[]; dimensions: TemplateOption[]; profiles: TemplateOption[] }
export const choiceTypes = new Set(['escolha__nica', 'caixas_de_sele__o', 'lista_suspensa', 'lista_multi_sele__o']);
export const dimensionTypes = new Set(['texto_curto', 'texto_longo', 'numero']);
export function canManageFormTemplates(access: { profile: { perfil: string }; sso?: { capabilities: readonly string[] } }) {
  return access.profile.perfil === 'administrador' && (!access.sso || access.sso.capabilities.includes('em.form_templates.manage'));
}
type Decimal = { integer: bigint; scale: number };
export function decimal(value: string): Decimal | null {
  if (value.length > 60 || !/^[+-]?(?:\d+(?:\.\d*)?|\.\d+)$/.test(value)) return null;
  const negative = value.startsWith('-'), unsigned = value.replace(/^[+-]/, ''), [whole, fraction = ''] = unsigned.split('.');
  const parsed = { integer: BigInt((whole || '0') + fraction) * (negative ? -1n : 1n), scale: fraction.length };
  if (parsed.integer > 1_000_000_000n * 10n ** BigInt(parsed.scale) || parsed.integer < -1_000_000_000n * 10n ** BigInt(parsed.scale)) return null;
  return parsed;
}
function scaled(value: Decimal, scale: number) { return value.integer * 10n ** BigInt(scale - value.scale); }
function decimalString(value: Decimal) {
  const sign = value.integer < 0 ? '-' : '', digits = (value.integer < 0 ? -value.integer : value.integer).toString().padStart(value.scale + 1, '0');
  const text = value.scale ? `${digits.slice(0, -value.scale)}.${digits.slice(-value.scale)}`.replace(/0+$/, '').replace(/\.$/, '') : digits;
  return `${sign}${text}`;
}
export function comparePositions(a: string, b: string) {
  const left = decimal(a), right = decimal(b); if (!left || !right) return left ? -1 : right ? 1 : 0;
  const scale = Math.max(left.scale, right.scale), difference = scaled(left, scale) - scaled(right, scale);
  return difference < 0 ? -1 : difference > 0 ? 1 : 0;
}
export function ordered<T extends { indice: string }>(rows: readonly T[]): T[] { return [...rows].sort((a, b) => comparePositions(a.indice, b.indice)); }
/** Creates an exact decimal between neighbours, without rounding the stored positions. */
export function positionBetween(before?: string, after?: string): string | null {
  const left = before == null ? null : decimal(before), right = after == null ? null : decimal(after);
  if ((before != null && !left) || (after != null && !right)) return null;
  let value: Decimal;
  if (left && right) {
    if (comparePositions(before!, after!) >= 0) return null;
    const scale = Math.max(left.scale, right.scale), total = scaled(left, scale) + scaled(right, scale);
    value = total % 2n === 0n ? { integer: total / 2n, scale } : { integer: total * 5n, scale: scale + 1 };
  } else if (left || right) { const reference = (left || right)!; value = { integer: reference.integer + (left ? 1n : -1n) * 10n ** BigInt(reference.scale), scale: reference.scale }; }
  else value = { integer: 1n, scale: 0 };
  const output = decimalString(value); return decimal(output) ? output : null;
}
export function positionWarnings(rows: readonly { indice: string }[], label: string): string[] {
  const exact = new Set<string>(), mobile = new Set<number>(), warnings = new Set<string>();
  for (const row of rows) {
    const parsed = decimal(row.indice);
    if (!parsed) { warnings.add(`${label}: há posições inválidas. Use um decimal de até 60 caracteres entre -1.000.000.000 e 1.000.000.000.`); continue; }
    const key = decimalString(parsed), number = Number(row.indice);
    if (exact.has(key)) warnings.add(`${label}: há posições repetidas.`);
    else if (mobile.has(number)) warnings.add(`${label}: duas posições distintas aparecem iguais no aplicativo. Normalize as posições antes de publicar.`);
    exact.add(key); mobile.add(number);
  }
  return [...warnings];
}
export function normalizeTemplatePositions(content: TemplateContent): TemplateContent {
  return { ...content, questions: ordered(content.questions).map((question, index) => ({ ...question, indice: String(index + 1), items: ordered(question.items).map((item, i) => ({ ...item, indice: String(i + 1) })) })) };
}
export function templateWarnings(content: TemplateContent): string[] {
  const warnings = [...positionWarnings(content.questions, 'Questões')];
  const ids = new Set<string>();
  if (!content.titulo.trim()) warnings.push('Informe o título do modelo.');
  if (!content.questions.some(question => question.tipo !== 'subt_tulo')) warnings.push('Inclua ao menos uma questão de preenchimento.');
  if (content.questions.length > 1000) warnings.push('O modelo aceita até 1.000 questões.');
  if (content.questions.reduce((sum, question) => sum + question.items.length, 0) > 5000) warnings.push('O modelo aceita até 5.000 opções no total.');
  for (const [index, question] of content.questions.entries()) {
    const name = `Questão ${index + 1}`;
    if (ids.has(question.id)) warnings.push('Existem identificações repetidas de questões ou opções.'); ids.add(question.id);
    if (!question.enunciado.trim()) warnings.push(`${name}: informe o enunciado.`);
    if (choiceTypes.has(question.tipo) && !question.items.length) warnings.push(`${name}: inclua ao menos uma opção.`);
    if (!choiceTypes.has(question.tipo) && question.items.length) warnings.push(`${name}: este tipo não usa opções. Remova-as conscientemente antes de publicar.`);
    if (question.subtipo && !((question.tipo === 'data' && question.subtipo === 'intervalo_de_datas') || (question.tipo === 'hora' && question.subtipo === 'intervalo_de_hor_rios'))) warnings.push(`${name}: o intervalo não corresponde ao tipo de resposta.`);
    if (question.dimensoes && !dimensionTypes.has(question.tipo)) warnings.push(`${name}: unidade disponível somente em respostas de texto ou número.`);
    if (question.colaborador_filtro_perfil && question.tipo !== 'colaborador') warnings.push(`${name}: o filtro de perfil pertence a questões de colaborador.`);
    warnings.push(...positionWarnings(question.items, `Opções da ${name.toLocaleLowerCase()}`));
    for (const item of question.items) { if (ids.has(item.id)) warnings.push('Existem identificações repetidas de questões ou opções.'); ids.add(item.id); if (!item.descricao.trim()) warnings.push(`${name}: preencha a descrição de todas as opções.`); }
  }
  if (formTemplateContentBytes(content) > 800_000) warnings.push('O conteúdo excedeu o limite de 800 KB. Reduza os textos antes de salvar ou publicar.');
  return [...new Set(warnings)];
}
export function blankQuestion(id: string, indice: string, tipo = 'texto_curto'): TemplateQuestion {
  return { id, indice, tipo, enunciado: '', title: null, subtitulo: null, tag: null, subtipo: null, dimensoes: null, obrigatorio: false, colaborador_filtro_perfil: null, items: [] };
}
export function templateSections(questions: readonly TemplateQuestion[]) {
  const sections: { id: string; title: string; description: string | null; questions: TemplateQuestion[] }[] = [];
  let current: typeof sections[number] | undefined;
  for (const question of ordered(questions)) {
    if (question.tipo === 'subt_tulo') { current = { id: question.id, title: question.enunciado || 'Subtítulo sem nome', description: question.subtitulo, questions: [] }; sections.push(current); }
    else { if (!current) { current = { id: 'general', title: 'Questões gerais', description: null, questions: [] }; sections.push(current); } current.questions.push(question); }
  }
  return sections;
}
import { formTemplateContentBytes } from '@/shared/form-template-size';


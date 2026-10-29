import { formTemplateContentSchema, type FormTemplateContent } from './form-template-policy';
import { uuid } from './policy';

type Raw = Record<string, any>;
const object = (value: unknown): Raw => {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error('O modelo retornado não pôde ser validado.');
  return value as Raw;
};
function ids(value: unknown): string[] { return Array.isArray(value) ? value.filter((item): item is string => uuid.safeParse(item).success) : []; }
export interface FormSourceMetadata { usa_aprovacao: boolean | null; has_cover: boolean; celulas_ids: string[]; equipes_ids: string[] }
export function formSourceMetadata(value: unknown): FormSourceMetadata {
  const raw = value && typeof value === 'object' && !Array.isArray(value) ? value as Raw : {};
  return { usa_aprovacao: typeof raw.usa_aprovacao === 'boolean' ? raw.usa_aprovacao : null,
    has_cover: typeof raw.imagem_capa_url === 'string' && !!raw.imagem_capa_url.trim(), celulas_ids: ids(raw.celulas_ids), equipes_ids: ids(raw.equipes_ids) };
}
export interface FormTemplateDraft {
  id: string; kind: 'new' | 'copy' | 'version'; state: 'draft' | 'published'; family_id: string | null;
  source_form_id: string | null; source_version: number | null; content: FormTemplateContent;
  source_snapshot: FormSourceMetadata; created_at: string; updated_at: string; published_form_id: string | null;
}
export interface FormTemplatePublication { form_id: string; version: number; id_mapping: { questions: Record<string, string>; items: Record<string, string> } }
function mapping(value: unknown): Record<string, string> {
  const raw = object(value ?? {}), output: Record<string, string> = {};
  for (const [key, target] of Object.entries(raw)) if (uuid.safeParse(key).success && uuid.safeParse(target).success) output[key] = target as string;
  return output;
}
export function formPublicationDto(value: unknown): FormTemplatePublication | null {
  if (value == null) return null;
  const raw = object(value), maps = object(raw.id_mapping ?? {});
  return { form_id: uuid.parse(raw.form_id), version: raw.version,
    id_mapping: { questions: mapping(maps.questions), items: mapping(maps.items) } };
}
export function formDraftDto(value: unknown): FormTemplateDraft {
  const raw = object(value);
  return { id: uuid.parse(raw.id), kind: raw.kind, state: raw.state, family_id: raw.family_id ?? null,
    source_form_id: raw.source_form_id ?? null, source_version: raw.source_version ?? null,
    content: formTemplateContentSchema.parse(raw.content), source_snapshot: formSourceMetadata(raw.source_snapshot),
    created_at: raw.created_at, updated_at: raw.updated_at, published_form_id: raw.published_form_id ?? null };
}
export function formTemplateSnapshotDto(value: unknown) {
  if (value == null) return null;
  const raw = object(value);
  return { draft: formDraftDto(raw.draft), publication: formPublicationDto(raw.publication) };
}
export function publishedFormSnapshotDto(value: unknown) {
  if (value == null) return null;
  const raw = object(value), form = object(raw.form);
  return { form: { id: uuid.parse(form.id), titulo: form.titulo as string, descricao: form.descricao as string | null,
    title: form.title as string | null, description: form.description as string | null, tipo: form.tipo as string | null, ativo: form.ativo as boolean },
    content: formTemplateContentSchema.parse(raw.content), source_snapshot: formSourceMetadata(raw.source_snapshot),
    version: (raw.version ?? 1) as number, family_id: (raw.family_id ?? null) as string | null };
}

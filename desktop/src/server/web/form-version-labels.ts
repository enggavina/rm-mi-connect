import type { SupabaseClient } from '@supabase/supabase-js';
import type { WebRow } from './data';

/** Display metadata only. Never changes a form's ID or adopts a new version. */
export async function withFormVersionLabels(client: SupabaseClient, forms: WebRow[]): Promise<WebRow[]> {
  const ids = [...new Set(forms.filter(form => !form.missing).map(form => form.id))];
  if (!ids.length) return forms;
  const versions = new Map<string, number>();
  for (let start = 0; start < ids.length; start += 100) {
    const selected = ids.slice(start, start + 100);
    const response = await client.from('rm_form_template_versions').select('form_id,version')
      .in('form_id', selected).order('form_id');
    if (response.error) throw Error('Não foi possível consultar as versões dos formulários. Tente novamente.');
    for (const row of response.data || []) {
      if (!selected.includes(row.form_id)) continue;
      if (!Number.isSafeInteger(row.version) || row.version < 1 || versions.has(row.form_id)) throw Error('A versão do formulário não pôde ser validada.');
      versions.set(row.form_id, row.version);
    }
  }
  return forms.map(form => {
    const version = versions.get(form.id);
    const title = form.titulo_modelo ?? form.titulo;
    return version === undefined ? form : { ...form, titulo_modelo: title, versao_modelo: version, titulo: `${title} · v${version}` };
  });
}

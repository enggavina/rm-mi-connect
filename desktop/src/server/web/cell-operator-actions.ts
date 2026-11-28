'use server';

import { revalidatePath } from 'next/cache';
import { getWebUser } from './auth';
import { cellOperatorChange, type CellOperatorActionState } from './cell-operator-access';
import { cellOperatorAccess } from './sso-bridge';
import { CorporateAuthError } from './sso-policy';
import { WorkshopContextError } from './workshop-context';

export async function changeCellOperator(_previous: CellOperatorActionState, form: FormData): Promise<CellOperatorActionState> {
  const input = cellOperatorChange.safeParse({
    cell: form.get('cell'), operator: form.get('operator'), enabled: form.get('enabled'), revision: form.get('revision'),
  });
  if (!input.success) return { error: true, message: 'Confira o vínculo e recarregue a célula.' };
  const { cell, operator, enabled, revision } = input.data;
  const path = `/cadastros/cells/${cell}/editar`;
  try {
    const access = await getWebUser(['em.catalogs.read', 'em.catalogs.manage']);
    if (access?.profile.perfil !== 'administrador' || !access.sso) {
      return { error: true, message: 'Entre como administrador da oficina para alterar os vínculos.' };
    }
    const result = await cellOperatorAccess(access.sso, cell, { operator, enabled: enabled === 'grant', revision });
    if (result.error?.code === 'PT409') {
      revalidatePath(path);
      return { error: true, message: 'O vínculo mudou. Confira a lista atualizada.' };
    }
    if (result.error?.code === '42501') return { error: true, message: 'O vínculo precisa ser confirmado nesta oficina.' };
    if (result.error || typeof result.data?.changed !== 'boolean') {
      return { error: true, message: 'Não foi possível confirmar a alteração. Atualize a célula para conferir o vínculo.' };
    }
    revalidatePath(path);
    return { error: false, message: result.data.changed ? (enabled === 'grant' ? 'Operador vinculado.' : 'Vínculo removido.') : 'A situação do vínculo já está atualizada.' };
  } catch (error) {
    if (error instanceof CorporateAuthError || error instanceof WorkshopContextError) {
      return { error: true, message: error.message };
    }
    return { error: true, message: 'Não foi possível confirmar a alteração. Atualize a célula para conferir o vínculo.' };
  }
}

export type StageAction = 'liberar' | 'retornar' | 'aprovar';
export interface StageApprovalRequest {
  submissionId: string;
  aprovacao_etapa_id: string;
  expected_updated_at: string;
  expected_cell_updated_at: string;
  acao: StageAction;
  observacao: string;
}
export const stageActionLabels: Record<StageAction, string> = {
  liberar: 'Liberar', retornar: 'Retornar', aprovar: 'Aprovar',
};
export const stageActionDescriptions: Record<StageAction, string> = {
  liberar: 'A liberação registra a decisão e prepara a etapa de retorno. A disponibilidade da célula de destino respeita as aprovações bloqueadoras do roteiro.',
  retornar: 'O retorno reprova esta etapa, reabre as liberações correspondentes e devolve a célula de destino para correção.',
  aprovar: 'A aprovação encerra a decisão desta etapa de retorno. As demais etapas pendentes continuam seguindo o roteiro.',
};
/** Presentation guard only. The server independently rechecks the operational rules. */
export function visibleStageActions(status: string | null | undefined, available: readonly StageAction[]): StageAction[] {
  const order: StageAction[] = status === 'retornado' ? ['retornar', 'aprovar'] : ['liberar'];
  return order.filter(action => available.includes(action));
}
/** A retry must retain the actor-free payload, exact timestamps and request identity. */
export function freezeStageApprovalRequest(request: StageApprovalRequest): Readonly<StageApprovalRequest> {
  return Object.freeze({ ...request });
}

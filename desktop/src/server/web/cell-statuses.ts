/** The existing rm_status_cel_proj_enum, scoped to Projeto + Célula. */
export const cellStatuses = ['pendente', 'retornado', 'liberado_para_ensaios_parciais', 'liberado_para_impregna__o',
  'liberado_para_montagem', 'para_execu__o', 'em_dia', 'finalizado', 'atrasado', 'n_a', 'aguardando_coleta', 'coletado'] as const;
export type CellStatus = typeof cellStatuses[number];
export const cellStatusLabels: Record<CellStatus, string> = {
  pendente: 'Pendente', retornado: 'Retornado', liberado_para_ensaios_parciais: 'Liberado para ensaios parciais',
  liberado_para_impregna__o: 'Liberado para impregnação', liberado_para_montagem: 'Liberado para montagem',
  para_execu__o: 'Para execução', em_dia: 'Executando', finalizado: 'Finalizado', atrasado: 'Atrasado', n_a: 'N/A',
  aguardando_coleta: 'Aguardando coleta', coletado: 'Coletado',
};
export const allocationStatusOptions = (existing: boolean) => cellStatuses.filter(status => existing || status !== 'retornado');

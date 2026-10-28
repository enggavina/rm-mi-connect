import { Text } from 'react-native';
import { router, type Href } from 'expo-router';
import { resolveJourneyContext, type JourneyContext } from '../domain/journey';
import { label } from '../domain/forms';
import { useApp, useRows } from './state';
import { Badge, Button, Card, Notice, Screen, s } from './components';

export function useJourney(cellId?: string, projectId?: string) {
  const app = useApp();
  const cells = useRows('rm_celulas'); const projects = useRows('rm_projetos'); const allocations = useRows('rm_celulas_projeto');
  return { context: resolveJourneyContext(app.operator, cellId, projectId, cells.rows, projects.rows, allocations.rows), error: cells.error || projects.error || allocations.error };
}

export function projectHref(context: JourneyContext): Href {
  return context.ok ? { pathname: '/projeto', params: { celula: context.cell.id, projeto: context.project.id } } : '/celula';
}

export function journeyLabel(context: JourneyContext): string {
  return context.ok ? `${context.cell.nome} · OS ${context.project.numero || context.allocation.numero_projeto}` : 'Célula · Projeto';
}

export function JourneyUnavailable({ context, error, title = 'Projeto indisponível' }: { context: JourneyContext; error?: string; title?: string }) {
  return <Screen title={title} backHref="/celula" backLabel="Escolher célula"><Notice error>{error || (!context.ok ? context.reason : 'Selecione novamente o projeto.')}</Notice><Button title="Escolher célula" onPress={() => router.replace('/celula')} /></Screen>;
}

export function ProjectSummary({ context }: { context: JourneyContext }) {
  if (!context.ok) return null;
  const { project, allocation } = context;
  return <Card><Badge text={label(allocation.status)} /><Text style={s.h2}>{project.nome || allocation.tipo_equipamento_nome_export || 'Equipamento'}</Text><Text style={s.body}>{project.cliente_nome_exportacao || allocation.cliente_nome_export || 'Cliente não informado'}</Text>{(project.escopo_abreviado || allocation.escopo_abreviado) && <Text style={s.muted}>{project.escopo_abreviado || allocation.escopo_abreviado}</Text>}{!context.canEdit && <Notice error>{allocation.motivo_bloqueio || 'Execução bloqueada pelo planejamento. A consulta continua disponível.'}</Notice>}</Card>;
}

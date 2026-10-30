import { Pressable, Text, View, useWindowDimensions } from 'react-native';
import { router, useLocalSearchParams, type Href } from 'expo-router';
import Feather from '@expo/vector-icons/Feather';
import { assignedForms, pendingProjectPhotos, projectPhotos, requiredPhotoProgress } from '../src/domain/journey';
import { galleryPhotos } from '../src/domain/gallery';
import { cellProjectStages } from '../src/domain/project-actions';
import { useRows } from '../src/ui/state';
import { useQueue } from '../src/ui/queue';
import { Badge, C, Notice, Screen, s } from '../src/ui/components';
import { JourneyUnavailable, ProjectSummary, journeyLabel, useJourney } from '../src/ui/journey';

export default function Projeto() {
  const { celula, projeto } = useLocalSearchParams<{ celula?: string; projeto?: string }>(); const { width } = useWindowDimensions();
  const { rows: queue, error: queueError } = useQueue();
  const { context, error } = useJourney(celula, projeto); const forms = useRows('rm_forms'); const records = useRows('rm_registros_formulario', { field: 'projeto_id', value: projeto }); const photos = useRows('rm_fotos', { field: 'projeto_id', value: projeto }); const stages = useRows('rm_aprovacoes_etapas', { field: 'projeto_id', value: projeto });
  if (!context.ok) return <JourneyUnavailable context={context} error={error} />;
  const assigned = assignedForms(context.allocation, forms.rows); const gallery = projectPhotos(context, photos.rows);
  const revisions = records.rows.filter(r => r.projeto_id === projeto && r.celula_id === celula && r.status === 'direcionado' && assigned.some(form => form.id === r.form_id)).length;
  const pending = pendingProjectPhotos(context, photos.rows, queue); const progress = requiredPhotoProgress(gallery.required, pending.slots);
  const approvals = cellProjectStages(context.allocation, stages.rows);
  const params = { celula: context.cell.id, projeto: context.project.id };
  const menus = [
    { title: 'Informações do projeto', icon: 'info' as const, route: '/informacoes-projeto', detail: 'Cliente, equipamento, prazos e planejamento' },
    { title: 'Formulários', icon: 'clipboard' as const, route: '/formularios', detail: `${assigned.length} vinculados${revisions ? ` · ${revisions} revisões solicitadas` : ''}` },
    { title: 'Galeria', icon: 'image' as const, route: '/galeria', detail: `${galleryPhotos(context, photos.rows, queue).length} fotos registradas no projeto` },
    { title: 'Registrar fotos', icon: 'camera' as const, route: '/registro-fotos', detail: 'Fotos obrigatórias ou complementares' },
    { title: 'Aprovações de etapas', icon: 'check-circle' as const, route: '/aprovacao', detail: `${approvals.filter(stage => stage.status === 'aprovado').length} aprovadas · ${approvals.filter(stage => !stage.status || stage.status === 'nulo').length} aguardando` },
    { title: 'Documentos', icon: 'folder' as const, route: '/documentos', detail: 'Anexos, nota fiscal e relatórios do projeto' },
    { title: 'Comentários', icon: 'message-circle' as const, route: '/comentarios', detail: 'Histórico e observações da célula' },
  ];
  return <Screen title={context.project.numero ? `OS ${context.project.numero}` : 'Projeto em recebimento'} eyebrow={journeyLabel(context)} backHref={{ pathname: '/projetos', params: { celula: context.cell.id } }} backLabel="Projetos da célula" subtitle="Acesse as informações e atividades deste projeto.">
    <ProjectSummary context={context} />
    {!!queueError && <Notice error>{queueError}</Notice>}
    <View style={s.row}><Badge text={`${progress.registered} de ${gallery.required.length} fotos obrigatórias registradas`} /><Badge text={`${progress.confirmed} confirmadas · ${progress.pending} salvas para envio`} alert={!!progress.pending} /></View>
    {!!progress.attention && <Notice error>Há um envio de foto que requer atenção. Consulte “Registrar fotos”.</Notice>}
    <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: 14 }}>{menus.map(menu => <Pressable key={menu.route} accessibilityRole="button" accessibilityLabel={menu.title} onPress={() => router.push({ pathname: menu.route, params } as Href)} style={({ pressed }) => [s.card, { flexBasis: width >= 700 ? '47%' : '100%', flexGrow: 1, minHeight: 142, opacity: pressed ? .7 : 1 }]}>
      <View style={[s.row, { justifyContent: 'space-between' }]}><Feather name={menu.icon} size={26} color={C.primary} /><Feather name="chevron-right" size={20} color={C.muted} /></View><Text style={s.h2}>{menu.title}</Text><Text style={s.muted}>{menu.detail}</Text>
    </Pressable>)}</View>
  </Screen>;
}

import { useState } from 'react';
import { Pressable, Text, View } from 'react-native';
import { useLocalSearchParams } from 'expo-router';
import Feather from '@expo/vector-icons/Feather';
import type { Row } from '../src/core';
import { label } from '../src/domain/forms';
import { useRows } from '../src/ui/state';
import { C, Card, Notice, Screen, s } from '../src/ui/components';
import { JourneyUnavailable, journeyLabel, projectHref, useJourney } from '../src/ui/journey';

type Detail = [string, unknown];
function Details({ title, values, initiallyOpen = false }: { title: string; values: Detail[]; initiallyOpen?: boolean }) {
  const [open, setOpen] = useState(initiallyOpen);
  const present = values.filter(([, value]) => value !== null && value !== undefined && value !== '');
  return <Card><Pressable accessibilityRole="button" accessibilityState={{ expanded: open }} onPress={() => setOpen(!open)} style={[s.row, { justifyContent: 'space-between', minHeight: 44 }]}><View style={{ flex: 1 }}><Text style={s.h2}>{title}</Text><Text style={s.muted}>{present.length} informações disponíveis</Text></View><Feather name={open ? 'chevron-up' : 'chevron-down'} size={22} color={C.primary} /></Pressable>
    {open && (!present.length ? <Text style={s.muted}>Nenhuma informação cadastrada nesta seção.</Text> : present.map(([caption, value]) => <View key={caption} style={{ borderTopWidth: 1, borderTopColor: C.line, paddingTop: 12, gap: 4 }}><Text style={s.muted}>{caption}</Text><Text selectable style={s.body}>{typeof value === 'boolean' ? value ? 'Sim' : 'Não' : String(value)}</Text></View>))}
  </Card>;
}
const date = (value?: string) => value && !Number.isNaN(Date.parse(value)) ? new Date(value).toLocaleString('pt-BR') : value;
const fields = (row: Row | undefined, mapping: [string, string][]): Detail[] => mapping.map(([caption, key]) => [caption, row?.[key]]);

export default function InformacoesProjeto() {
  const { celula, projeto } = useLocalSearchParams<{ celula?: string; projeto?: string }>(); const { context, error } = useJourney(celula, projeto);
  const clients = useRows('rm_clientes'); const equipment = useRows('rm_equipamentos'); const users = useRows('rm_users'); const types = useRows('rm_tipos_equipamento');
  if (!context.ok) return <JourneyUnavailable context={context} error={error} />;
  const p = context.project, a = context.allocation; const e = equipment.rows.find(row => row.projeto_id === p.id); const customer = clients.rows.find(row => row.id === p.cliente_id);
  const person = (id?: string) => users.rows.find(user => user.id === id)?.nome;
  const typeName = types.rows.find(type => type.id === (p.tipo_equipamento_id || e?.tipo_equipamento_id))?.nome || a.tipo_equipamento_nome_export;
  return <Screen title="Informações do projeto" eyebrow={journeyLabel(context)} backHref={projectHref(context)} backLabel="Detalhe do projeto" subtitle="Dados cadastrados do cliente, equipamento e execução.">
    {(clients.error || equipment.error || users.error || types.error) && <Notice error>{clients.error || equipment.error || users.error || types.error}</Notice>}
    <Details initiallyOpen title="Cliente e projeto" values={[
      ['Número / OS', p.numero || 'Aguardando numeração pelo planejamento'], ['Nome', p.nome], ['Cliente', customer?.nome || p.cliente_nome_exportacao || a.cliente_nome_export], ['Código do cliente', customer?.codigo], ['Sobre o cliente', customer?.descricao],
      ['Contato', p.contato], ['Proprietário', p.proprietario], ['Parceiro', p.nome_parceiro], ['Tipo de equipamento', typeName], ['Descrição do equipamento', p.descricao_equipamento || e?.descricao], ['Escopo', p.escopo_abreviado], ['Descrição do escopo', p.descricao_cod_escopo],
      ['Status do projeto', label(p.status)], ['Status do planejamento', label(p.status_pcp)], ['Gestor responsável', person(p.gestor_responsavel_id)], ['Cadastrado por', person(p.created_by_user_id)], ['Unidade de negócio', p.unidade_de_negocio_bu], ['Centro de resultado', p.centro_de_resultado], ['Número da nota fiscal', p.nota_fiscal], ['Eventualidades', p.eventualidades],
    ]} />
    <Details title="Prazos e datas" values={[
      ['Chegada do equipamento', date(p.chegada_do_equipamento)], ['Nota de entrada', date(p.data_nota_entrada)], ['Início previsto', date(p.data_prevista_inicio)], ['Fim previsto', date(p.data_prevista_final)], ['Data contratual', date(p.data_contratual)], ['Data renegociada', date(p.data_renegociada)], ['Prazo de execução', p.prazo_execucao], ['Início do delineamento', date(p.data_inicio_delineamento)], ['Fim do delineamento', date(p.data_final_delineamento)], ['Envio para o comercial', date(p.data_envio_para_comercial)], ['Handover', date(p.data_de_handover)], ['Entrega realizada', date(p.data_real_de_entrega)], ['Motivo do replanejamento', p.replanejamento_motivo], ['Cadastro', date(p.created_at)], ['Última atualização', date(p.updated_at)],
    ]} />
    <Details title="Identificação do equipamento" values={[
      ['Placa do motor', e?.placa_motor ? e.placa_motor === 'c___placa' ? 'Com placa' : 'Sem placa' : null], ...fields(e, [['Descrição', 'descricao'], ['Fabricante', 'fabricante'], ['Modelo', 'modelo'], ['Número de série', 'numero_serie'], ['Embarcação', 'embarcacao'], ['Certificado', 'certificado'], ['Norma', 'norma']]),
    ]} />
    <Details title="Dados elétricos" values={fields(e, [['Potência', 'potencia'], ['Rotação', 'rotacao'], ['Tensão do estator', 'tensao_estator'], ['Tipo de tensão', 'tipo_tensao'], ['Corrente do estator', 'corrente_estator'], ['Corrente de partida', 'corrente_partida'], ['Frequência', 'frequencia'], ['Classe de isolamento', 'classe_isolamento'], ['Fator de potência', 'fp'], ['Fator de serviço', 'fs'], ['Número de cabos', 'numero_cabos'], ['Ligação', 'ligacao']])} />
    <Details title="Construção e condição cadastrada" values={[
      ...fields(e, [['Grau IP', 'grau_ip'], ['Forma', 'forma'], ['Regime', 'regime'], ['Peso', 'peso'], ['Componentes', 'componentes']]),
      ['Desmontar para orçar', e?.desmontar_para_orcar ? label(e.desmontar_para_orcar) : null], ['Ensaiar antes de desmontar', e?.ensaiar_antes_desmontar ? label(e.ensaiar_antes_desmontar) : null], ['Teste intermediário', e?.teste_intermediario ? label(e.teste_intermediario) : null],
    ]} />
    <Details title={`Execução · ${context.cell.nome}`} values={[
      ['Status', label(a.status)], ['Histórico de status', (a.status_historico || []).map(label).join(' → ')], ['Responsável', person(a.responsavel_id)], ['Equipe', a.equipe], ['Oficina', a.oficina], ['Prioridade', a.prioridade], ['Criticidade', a.criticidade], ['Horas previstas', a.horas_previstas], ['Horas realizadas', a.horas_realizadas], ['Início', date(a.data_inicio)], ['Prazo', date(a.data_limite)], ['Fim realizado', date(a.data_fim_real)], ['Replanejada em', date(a.replanejada_em)], ['Replanejada por', person(a.replanejada_por_id)], ['Última alteração por', person(a.modified_by_id)], ['Bloqueada', a.bloqueada === 'sim'], ['Motivo do bloqueio', a.motivo_bloqueio], ['Motivo do atraso', a.motivo_atraso], ['Observação', a.observacao], ['Dependências', a.depende_de],
    ]} />
  </Screen>;
}

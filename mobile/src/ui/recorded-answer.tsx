import { Text, View } from 'react-native';
import type { Row } from '../core';
import { hasQuestionId, type DisplayAnswer } from '../domain/forms';
import { Badge, Button, Card, Notice, s } from './components';
import { MediaImage } from './media';

function formatDate(value: string, time = false) {
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? value : time ? date.toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' }) : date.toLocaleDateString('pt-BR');
}

export function RecordedAnswer({ question, answer, onCorrect }: { question: Row; answer?: DisplayAnswer; onCorrect?: () => void }) {
  const na = answer?.is_na || answer?.resposta === 'N/A';
  const photos = answer?.fotos_urls ?? [];
  const hasContent = answer && (na || answer.resposta || answer.itens?.length || photos.some(Boolean) || answer.assinatura_url || answer.date_inicio || answer.data_fim || answer.hora);
  return <Card><Text style={s.h2}>{question.indice}. {question.enunciado}</Text>{!!question.dimensoes && <Text style={s.muted}>Unidade: {String(question.dimensoes).replace(/_/g, ' ')}</Text>}
    {answer && !hasQuestionId(answer) ? <Text style={s.muted}>Resposta histórica disponível somente para consulta.</Text> : answer?.revisar && <Badge text="Correção solicitada" alert />}
    {na ? <Notice>Não se aplica (N/A)</Notice> : <>
      {!!answer?.resposta && <Text selectable style={s.body}>{answer.resposta}</Text>}
      {(answer?.itens ?? []).filter(value => value !== answer?.resposta).map((value, index) => <Text key={index} selectable style={s.body}>• {value}</Text>)}
      {!!answer?.date_inicio && <Text style={s.body}>{answer.data_fim ? 'Início: ' : ''}{formatDate(answer.date_inicio, question.tipo === 'hora')}</Text>}
      {!!answer?.data_fim && <Text style={s.body}>Fim: {formatDate(answer.data_fim, question.tipo === 'hora')}</Text>}
      {!!answer?.hora && !answer.date_inicio && <Text style={s.body}>{formatDate(answer.hora, true)}</Text>}
      {photos.map((uri, index) => uri ? <View key={index} style={{ gap: 8 }}>{question.tipo === 'foto_antes_depois' && <Text style={s.muted}>{index === 0 ? 'Antes' : 'Depois'}</Text>}<MediaImage uri={uri} /></View> : null)}
      {!!answer?.assinatura_url && <MediaImage uri={answer.assinatura_url} height={150} />}
      {!hasContent && <Text style={s.muted}>Sem resposta registrada.</Text>}
    </>}
    {onCorrect && hasQuestionId(answer) && <Button secondary title="Corrigir esta questão" onPress={onCorrect} />}
  </Card>;
}

import type { ReactNode } from 'react';
import { Pressable, Text, View } from 'react-native';
import Feather from '@expo/vector-icons/Feather';
import type { Row } from '../core';
import { answerHasValue, hasQuestionId, type DisplayAnswer, type FormSection } from '../domain/forms';
import { Badge, Button, C, s } from './components';

export function FormSections({ sections, expandedId, answers, errors, disabled, onToggle, onListLayout, onSectionLayout, renderQuestion }: {
  sections: FormSection[]; expandedId: string | null; answers: Record<string, DisplayAnswer>; errors: Record<string, string>;
  disabled?: boolean; onToggle: (section: FormSection) => void; onListLayout: (y: number) => void; onSectionLayout: (id: string, y: number) => void; renderQuestion: (question: Row) => ReactNode;
}) {
  return <View style={{ gap: 18 }} onLayout={event => onListLayout(event.nativeEvent.layout.y)}>
    {sections.map(section => {
      const expanded = !section.subtitle || section.id === expandedId;
      const answered = section.questions.filter(question => answerHasValue(question, answers[question.id])).length;
      const revisions = section.questions.filter(question => hasQuestionId(answers[question.id]) && answers[question.id]?.revisar).length;
      const invalid = section.questions.filter(question => !!errors[question.id]).length;
      return <View key={section.id} style={{ gap: 14 }} onLayout={event => onSectionLayout(section.id, event.nativeEvent.layout.y)}>
        {section.subtitle && <Pressable accessibilityRole="button" accessibilityLabel={`${expanded ? 'Recolher' : 'Expandir'} ${section.title}`} accessibilityState={{ expanded, disabled: !!disabled }} disabled={disabled} onPress={() => onToggle(section)}
          style={({ pressed }) => ({ backgroundColor: C.white, borderWidth: 1, borderColor: invalid ? C.danger : C.line, borderLeftWidth: 4, borderLeftColor: C.primary, borderRadius: 12, padding: 18, gap: 10, opacity: pressed ? .85 : 1 })}>
          <View style={[s.row, { flexWrap: 'nowrap' }]}><Text style={[s.h2, { flex: 1 }]}>{section.title}</Text><Feather name={expanded ? 'chevron-up' : 'chevron-down'} size={24} color={C.primary} /></View>
          {!!section.description && <Text style={s.muted}>{section.description}</Text>}
          <View style={s.row}><Badge text={`${answered} de ${section.questions.length} respondidas`} />{!!revisions && <Badge text={`${revisions} em revisão`} alert />}{!!invalid && <Badge text={`${invalid} com pendência`} alert />}</View>
          <Text style={{ color: C.primary, fontSize: 14, fontWeight: '600' }}>{expanded ? 'Recolher questões' : 'Toque para ver as questões'}</Text>
        </Pressable>}
        {expanded && section.questions.map(renderQuestion)}
      </View>;
    })}
  </View>;
}

export function CollapseSection({ section, disabled, onCollapse }: { section: FormSection; disabled?: boolean; onCollapse: () => void }) {
  return <View style={{ width: '100%', maxWidth: 1200, alignSelf: 'center', gap: 7 }}>
    <Text numberOfLines={1} style={[s.muted, { fontWeight: '600' }]}>{section.title}</Text>
    <Button secondary title="Recolher subtítulo" disabled={disabled} onPress={onCollapse} />
  </View>;
}

import { Text, View } from 'react-native';
import { Button, s } from './components';

export function PageControls({ page, pages, onChange }: { page: number; pages: number; onChange: (page: number) => void }) {
  if (pages <= 1) return null;
  return <View style={s.row}><Button secondary title="Anterior" disabled={page === 0} onPress={() => onChange(page - 1)} /><Text style={s.muted}>Página {page + 1} de {pages}</Text><Button secondary title="Próxima" disabled={page + 1 === pages} onPress={() => onChange(page + 1)} /></View>;
}

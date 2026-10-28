import { useLocalSearchParams } from 'expo-router';
import { FormList } from '../src/ui/form-list';
export default function Peritagem() { const p = useLocalSearchParams<{ projeto?: string; celula?: string }>(); return <FormList peritagem projectId={p.projeto} cellId={p.celula} />; }

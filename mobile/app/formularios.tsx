import { useLocalSearchParams } from 'expo-router';
import { FormList } from '../src/ui/form-list';
export default function Formularios() { const p = useLocalSearchParams<{projeto?:string;celula?:string}>(); return <FormList projectId={p.projeto} cellId={p.celula} />; }

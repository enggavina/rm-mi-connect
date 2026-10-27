import { useLocalSearchParams } from 'expo-router';
import { FormScreen } from '../src/ui/form-screen';
export default function RegistroForm() { const p = useLocalSearchParams<{ projeto: string; celula: string; form: string }>(); return <FormScreen projectId={p.projeto} cellId={p.celula} formId={p.form} />; }

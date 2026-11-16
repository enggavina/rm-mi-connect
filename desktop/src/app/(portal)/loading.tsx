import { MiLoader } from '@/components/web/mi-loader';

export default function Loading() {
  return <div className="loading-view"><MiLoader label="Carregando os dados da operação…" /></div>;
}

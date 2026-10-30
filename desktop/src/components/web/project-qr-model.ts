import type { ProjectQrProject } from '@/server/web/project-qr-policy';

const canonicalId = (value: string) => {
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value)) throw new Error('Projeto inválido.');
  return value.toLowerCase();
};
export const projectQrImageHref = (id: string, download = false) => `/api/web/projects/${canonicalId(id)}/qr${download ? '?download=1' : ''}`;
export function projectQrLabel(project: Pick<ProjectQrProject, 'numero'>) {
  return project.numero?.trim() ? `OS ${project.numero.trim()}` : 'Projeto em recebimento';
}
/** A short visible description supports a label; only the UUID enters the QR. */
export function projectQrSummary(project: Pick<ProjectQrProject, 'nome' | 'descricao_equipamento'>) {
  const text = project.nome?.trim() || project.descricao_equipamento?.trim() || '';
  const characters = Array.from(text);
  return characters.length > 240 ? `${characters.slice(0, 240).join('')}…` : text;
}

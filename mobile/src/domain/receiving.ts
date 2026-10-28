// Canonical RMTipoFoto captions/slugs from migration 001. The historical
// `vista_superior` slug is intentionally displayed as "Vista Traseira".
export const RECEIVING_PHOTO_TITLES = [
  { value: 'lateral_direita', label: 'Vista lateral direita' },
  { value: 'lateral_esquerda', label: 'Vista lateral esquerda' },
  { value: 'frente', label: 'Vista frontal' },
  { value: 'vista_superior', label: 'Vista Traseira' },
  { value: 'placa', label: 'Placa de identificação' },
  { value: 'antes_de_descarregar', label: 'Antes de descarregar' },
  { value: 'embalagem', label: 'Embalagem' },
  { value: 'em_cima_do_caminh_o_lonado', label: 'Em cima do caminhão lonado' },
] as const;
export type ReceivingPhotoType = typeof RECEIVING_PHOTO_TITLES[number]['value'];
export type ReceivingPhoto = { id: string; uri: string; tipo: string; comentario: string };
export type Receiving = {
  version: 2; id: string; step: number; cliente: string; chegada: string;
  notaFiscal: string; arquivoNotaFiscal: string; descricaoEquipamento: string;
  placaMotor: string; eventualidades: string; fotos: ReceivingPhoto[];
  equipamento: Record<string, unknown>;
  // Previously entered fields remain in storage and in the legacy envelope.
  tipo?: string; numero?: string; nome?: string; contato?: string; proprietario?: string;
  projeto_id?: string; qr?: string; submitted?: boolean;
  legacySnapshot?: Record<string, unknown>;
};
export const RECEIVING_STEPS = ['Cliente e projeto', 'Fotos', 'Conferência'] as const;
const text = (value: unknown) => typeof value === 'string' ? value : '';
const object = (value: unknown): Record<string, unknown> => value && typeof value === 'object' && !Array.isArray(value) ? value as Record<string, unknown> : {};

export function newReceiving(id: string, now: string): Receiving {
  return { version: 2, id, step: 0, cliente: '', chegada: now, notaFiscal: '', arquivoNotaFiscal: '',
    descricaoEquipamento: '', placaMotor: '', eventualidades: '', equipamento: {}, fotos: [] };
}
export function restoreReceiving(saved: unknown, fallbackId: string, now: string): Receiving {
  if (saved == null) return newReceiving(fallbackId, now);
  const old = object(saved), id = text(old.id), eq = object(old.equipamento);
  if (!id) throw new Error('O rascunho salvo está sem protocolo. Seus dados foram preservados para recuperação.');
  const wasCurrent = old.version === 2;
  const oldStep = typeof old.step === 'number' && Number.isFinite(old.step) ? old.step : 0;
  const step = wasCurrent ? Math.max(0, Math.min(2, Math.floor(oldStep))) : oldStep >= 6 ? 2 : oldStep === 5 ? 1 : 0;
  const photos: ReceivingPhoto[] = (Array.isArray(old.fotos) ? old.fotos : []).map((photo, index) => {
    if (typeof photo === 'string') return { id: `${id}:legacy-photo:${index}`, uri: photo, tipo: '', comentario: '' };
    const entry = object(photo);
    return { ...entry, id: text(entry.id) || `${id}:photo:${index}`, uri: text(entry.uri), tipo: text(entry.tipo), comentario: text(entry.comentario) };
  });
  return { ...old, version: 2, id, step, cliente: text(old.cliente), chegada: text(old.chegada),
    notaFiscal: text(old.notaFiscal), arquivoNotaFiscal: text(old.arquivoNotaFiscal),
    descricaoEquipamento: typeof old.descricaoEquipamento === 'string' ? old.descricaoEquipamento : text(eq.descricao),
    placaMotor: typeof old.placaMotor === 'string' ? old.placaMotor : text(eq.placa_motor),
    eventualidades: text(old.eventualidades), equipamento: eq, fotos: photos,
    ...(!wasCurrent ? { legacySnapshot: old } : {}),
  } as Receiving;
}
export function receivingPhotoTitle(type: string): string | undefined {
  return RECEIVING_PHOTO_TITLES.find(option => option.value === type)?.label;
}
export function setArrivalPart(iso: string, selected: Date, part: 'date' | 'time'): string {
  const result = Number.isFinite(Date.parse(iso)) ? new Date(iso) : new Date(selected);
  if (part === 'date') result.setFullYear(selected.getFullYear(), selected.getMonth(), selected.getDate());
  else result.setHours(selected.getHours(), selected.getMinutes(), 0, 0);
  return result.toISOString();
}
export function validateReceiving(data: Receiving, includePhotos = true): string | null {
  if (!data.cliente) return 'Selecione o cliente.';
  if (!Number.isFinite(Date.parse(data.chegada))) return 'Informe uma data e uma hora de chegada válidas.';
  if (data.placaMotor && !['c___placa', 's___placa'].includes(data.placaMotor)) return 'Selecione a condição da placa do motor.';
  if (includePhotos) {
    if (!data.fotos.some(photo => photo.uri)) return 'Registre ao menos uma foto de recebimento.';
    if (data.fotos.some(photo => photo.uri && !receivingPhotoTitle(photo.tipo))) return 'Escolha um título cadastrado para cada foto preservada do rascunho anterior.';
  }
  return null;
}
export function receivingPayload(data: Receiving): Record<string, unknown> {
  const error = validateReceiving(data); if (error) throw new Error(error);
  const equipment: Record<string, unknown> = { ...data.equipamento, descricao: data.descricaoEquipamento.trim(), placa_motor: data.placaMotor || null };
  // Keep the previous wizard's numeric conversion for its preserved values.
  for (const key of ['fp', 'fs', 'numero_cabos']) {
    const raw = equipment[key];
    if (typeof raw === 'string' && raw.trim()) {
      const value = Number(raw.replace(',', '.'));
      if (Number.isFinite(value) && (key !== 'numero_cabos' || (Number.isInteger(value) && value >= 0))) equipment[key] = value;
    }
  }
  const params: Record<string, unknown> = {
    p_cliente_id: data.cliente, p_chegada_equipamento: data.chegada,
    p_nota_fiscal: data.notaFiscal.trim() || null, p_arquivo_nota_fiscal_url: data.arquivoNotaFiscal || null,
    p_descricao_equipamento: data.descricaoEquipamento.trim(), p_eventualidades: data.eventualidades,
    p_equipamento: equipment,
    p_fotos_recebimento: data.fotos.filter(photo => photo.uri).map((photo, index) => ({
      foto_url: photo.uri, titulo: receivingPhotoTitle(photo.tipo), tipo_recebimento: photo.tipo,
      legenda: photo.comentario.trim() || null, numero: index + 1, categoria_foto: 'obrigat_ria',
    })),
  };
  // New drafts do not synthesize an OS, equipment type, name or owner.
  for (const [local, remote] of [['tipo', 'p_tipo_equipamento_id'], ['numero', 'p_numero_projeto'], ['nome', 'p_nome_projeto'],
    ['contato', 'p_contato'], ['proprietario', 'p_proprietario'], ['projeto_id', 'p_projeto_id'], ['qr', 'p_qrcode_value']] as const) {
    if (data[local]) params[remote] = data[local];
  }
  return params;
}

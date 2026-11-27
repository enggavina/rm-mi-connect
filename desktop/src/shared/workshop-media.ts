export type WorkshopMediaSource = 'project_photo' | 'answer_photo' | 'answer_signature';

export function workshopMediaUrl(id: string, source: WorkshopMediaSource, index?: number) {
  return `/api/web/media/${id}?source=${source}${index === undefined ? '' : `&index=${index}`}`;
}

export function isWorkshopMediaUrl(value: string) {
  return /^\/api\/web\/media\/[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\?source=(?:project_photo|answer_signature|answer_photo&index=(?:0|[1-9]\d{0,5}))$/.test(value);
}

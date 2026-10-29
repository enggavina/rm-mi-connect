const utf8 = new TextEncoder();
/** PostgreSQL jsonb::text adds spaces after commas and colons. Key order does not affect the byte count. */
export function formTemplateContentBytes(value: unknown): number {
  if (value === null || typeof value === 'string' || typeof value === 'boolean' || typeof value === 'number' && Number.isFinite(value)) return utf8.encode(JSON.stringify(value)).byteLength;
  if (Array.isArray(value)) return 2 + Math.max(0, value.length - 1) * 2 + value.reduce((sum, item) => sum + formTemplateContentBytes(item), 0);
  if (typeof value === 'object' && value !== null) {
    const entries = Object.entries(value);
    return 2 + Math.max(0, entries.length - 1) * 2 + entries.reduce((sum, [key, item]) => sum + utf8.encode(JSON.stringify(key)).byteLength + 2 + formTemplateContentBytes(item), 0);
  }
  throw new TypeError('O conteúdo deve conter somente valores JSON válidos.');
}

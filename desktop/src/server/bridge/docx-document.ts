/** Identify the ZIP container without inflating any entries from the historical file. */
export function isWordDocument(bytes: Buffer): boolean {
  if (bytes.length < 22 || bytes.readUInt32LE(0) !== 0x04034b50) return false;
  const endOffset = bytes.lastIndexOf(Buffer.from('504b0506', 'hex'), bytes.length - 22);
  if (endOffset < bytes.length - 22 - 65_535 || endOffset < 0
    || endOffset + 22 + bytes.readUInt16LE(endOffset + 20) !== bytes.length
    || bytes.readUInt32LE(endOffset + 4) !== 0) return false;
  const entries = bytes.readUInt16LE(endOffset + 10);
  const start = bytes.readUInt32LE(endOffset + 16);
  if (entries !== bytes.readUInt16LE(endOffset + 8) || !entries || start + bytes.readUInt32LE(endOffset + 12) !== endOffset) return false;

  let offset = start;
  const required = new Set(['[Content_Types].xml', 'word/document.xml']);
  for (let i = 0; i < entries; i++) {
    if (offset + 46 > endOffset || bytes.readUInt32LE(offset) !== 0x02014b50) return false;
    const filenameLength = bytes.readUInt16LE(offset + 28);
    const filenameEnd = offset + 46 + filenameLength;
    const next = filenameEnd + bytes.readUInt16LE(offset + 30) + bytes.readUInt16LE(offset + 32);
    if (next > endOffset) return false;
    const name = bytes.toString('utf8', offset + 46, filenameEnd);
    if (required.has(name)) {
      const local = bytes.readUInt32LE(offset + 42);
      if (local + 30 + filenameLength > start || bytes.readUInt32LE(local) !== 0x04034b50
        || (bytes.readUInt16LE(offset + 8) & 1) || (bytes.readUInt16LE(local + 6) & 1)
        || filenameLength !== bytes.readUInt16LE(local + 26) || bytes.toString('utf8', local + 30, local + 30 + filenameLength) !== name) return false;
      required.delete(name);
    }
    offset = next;
  }
  return offset === endOffset && required.size === 0;
}

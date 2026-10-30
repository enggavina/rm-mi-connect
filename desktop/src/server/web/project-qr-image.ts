import QRCode from 'qrcode';
import { projectQrValue } from './project-qr-policy';

/** Local SVG generation only. No image service, fetch, database update or Storage object. */
export async function renderProjectQrSvg(projectId: string): Promise<string> {
  return QRCode.toString(projectQrValue(projectId), { type: 'svg', width: 512, margin: 4,
    errorCorrectionLevel: 'Q', color: { dark: '#000000ff', light: '#ffffffff' } });
}

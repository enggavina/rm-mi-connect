const baseDatabase = 'rm-mi-connect.db';
const workshopId = /^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/i;

export class WorkshopRestartRequired extends Error {
  readonly code = '42501';

  constructor() {
    super('Acessos confirmou a nova oficina. Reabra o app para continuar. Os trabalhos anteriores estão guardados.');
  }
}

/** The first confirmed office keeps the existing on-device database. */
export function workshopDatabaseName(office: string | null, baseOffice: string | null): string {
  if ((office && !workshopId.test(office)) || (baseOffice && !workshopId.test(baseOffice))) {
    throw new Error('Não foi possível identificar o armazenamento da oficina. Os dados locais foram preservados.');
  }
  return !office || !baseOffice || office.toLowerCase() === baseOffice.toLowerCase()
    ? baseDatabase : `rm-mi-connect-${office.toLowerCase()}.db`;
}

export const androidPilotRelease = {
  version: '1.2.28',
  build: 31,
  bucket: 'rm-aplicativo-android',
  file: 'em-mi-electric-brasil-1.2.28-piloto.apk',
  mime: 'application/vnd.android.package-archive',
  platformOrigin: 'https://ellpxfbsrbhblyizvbbk.supabase.co',
  bytes: 38739748,
  sha256: '0ea881332d138809350fd089bb7c4e92e26b3cd099113e064a7050589ba48adf',
} as const;

export const androidPilotKey = `${androidPilotRelease.version}/${androidPilotRelease.sha256}/${androidPilotRelease.file}`;

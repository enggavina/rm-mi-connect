export const androidPilotRelease = {
  version: '1.2.29',
  build: 32,
  bucket: 'rm-aplicativo-android',
  file: 'em-mi-electric-brasil-1.2.29-piloto.apk',
  mime: 'application/vnd.android.package-archive',
  platformOrigin: 'https://ellpxfbsrbhblyizvbbk.supabase.co',
  bytes: 38740564,
  sha256: 'f64fbf38b861e44662a82e309eda51528e7346c4fee9826b13a6dd1b38a64ebb',
} as const;

export const androidPilotKey = `${androidPilotRelease.version}/${androidPilotRelease.sha256}/${androidPilotRelease.file}`;

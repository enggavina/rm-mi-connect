export const androidPilotRelease = {
  version: '1.2.26',
  build: 29,
  bucket: 'rm-aplicativo-android',
  file: 'em-mi-electric-brasil-1.2.26-piloto.apk',
  mime: 'application/vnd.android.package-archive',
  platformOrigin: 'https://ellpxfbsrbhblyizvbbk.supabase.co',
  bytes: 38739216,
  sha256: '78043549a0d9af89f5b8640c2ddc1b9b729444c268e48d0bf023ec946f8081d2',
} as const;

export const androidPilotKey = `${androidPilotRelease.version}/${androidPilotRelease.sha256}/${androidPilotRelease.file}`;

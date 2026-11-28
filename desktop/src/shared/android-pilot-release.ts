export const androidPilotRelease = {
  version: '1.2.27',
  build: 30,
  bucket: 'rm-aplicativo-android',
  file: 'em-mi-electric-brasil-1.2.27-piloto.apk',
  mime: 'application/vnd.android.package-archive',
  platformOrigin: 'https://ellpxfbsrbhblyizvbbk.supabase.co',
  bytes: 38739332,
  sha256: '33d8a596149f0c0dabedde575457cac39491d457672eb49d18ab322935c9d1e0',
} as const;

export const androidPilotKey = `${androidPilotRelease.version}/${androidPilotRelease.sha256}/${androidPilotRelease.file}`;

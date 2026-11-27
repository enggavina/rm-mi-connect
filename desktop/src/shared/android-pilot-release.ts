export const androidPilotRelease = {
  version: '1.2.26',
  build: 29,
  architecture: 'arm64-v8a',
  bucket: 'rm-aplicativo-android',
  file: 'em-mi-electric-brasil-1.2.26-arm64.apk',
  mime: 'application/vnd.android.package-archive',
  platformOrigin: 'https://ellpxfbsrbhblyizvbbk.supabase.co',
  bytes: 30047305,
  sha256: 'ea523e91031e5cb543d413ec7d4327d92cb8dce52ff01d36e416b75157b45281',
} as const;

export const androidPilotKey = `${androidPilotRelease.version}/${androidPilotRelease.sha256}/${androidPilotRelease.file}`;

export const androidPilotRelease = {
  version: '1.2.26',
  build: 29,
  architecture: 'arm64-v8a',
  bucket: 'rm-aplicativo-android',
  file: 'em-mi-electric-brasil-1.2.26-arm64.apk',
  mime: 'application/vnd.android.package-archive',
  platformOrigin: 'https://ellpxfbsrbhblyizvbbk.supabase.co',
  bytes: 44684861,
  sha256: '524a4c804fe8d5f9a6a0dc1e1af31a9c964d76d9de26eb2ebc175c2cf9dbe3c8',
} as const;

export const androidPilotKey = `${androidPilotRelease.version}/${androidPilotRelease.sha256}/${androidPilotRelease.file}`;

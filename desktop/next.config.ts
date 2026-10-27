import type { NextConfig } from 'next';
import path from 'node:path';
const config: NextConfig = {
  output: 'standalone', poweredByHeader: false, outputFileTracingRoot: path.resolve(process.cwd()),
  // Keep CI/Railway builds within a modest memory budget, including on large-core hosts.
  experimental: { cpus: 2 },
};
export default config;

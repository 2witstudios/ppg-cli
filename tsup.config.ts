import { defineConfig } from 'tsup';

export default defineConfig({
  entry: ['src/cli.ts'],
  format: ['esm'],
  target: 'node20',
  banner: { js: '#!/usr/bin/env node' },
  clean: true,
  sourcemap: true,
  dts: false,
  splitting: false,
  noExternal: [],
});

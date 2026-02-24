# Contributing to ppg-cli

## Prerequisites

- Node.js >= 20
- git
- tmux

## Setup

```bash
git clone https://github.com/2witstudios/ppg-cli.git
cd ppg-cli
npm install
```

## Development

```bash
npm run dev          # Run CLI via tsx (unbundled, fast iteration)
npm run build        # Build with tsup → dist/cli.js
npm test             # Run tests with Vitest
npm run typecheck    # Type-check with tsc --noEmit
```

## Code Conventions

- **TypeScript strict mode** — ES2022, NodeNext module resolution, ESM-only
- **`.js` extensions in imports** — Required by NodeNext (e.g., `import { foo } from './bar.js'`)
- **Functional style** — Pure functions, composition, `const`, destructuring, no classes except `PgError`
- **Dual output** — Every command supports `--json`. Use `output()` and `outputError()` from `lib/output.ts`
- **Manifest locking** — Always use `updateManifest()` for read-modify-write, never read + write separately
- **Colocated tests** — Test files live next to source (e.g., `src/core/manifest.test.ts`)
- **Test naming** — `describe('unitName')` → `test('given X, should Y')`

## Project Structure

```
src/
├── cli.ts              # Entry point — registers commands
├── commands/           # Command implementations
├── core/               # Domain logic
├── lib/                # Utilities
└── types/              # Type definitions
```

Flow: `cli.ts` → `commands/` → `core/` → `lib/` → `types/`

## Pull Requests

1. Fork the repo and create a branch from `main`
2. Make your changes
3. Add/update tests for any new behavior
4. Ensure `npm test` and `npm run typecheck` pass
5. Open a PR with a clear description of the change

## License

By contributing, you agree that your contributions will be licensed under the MIT License.

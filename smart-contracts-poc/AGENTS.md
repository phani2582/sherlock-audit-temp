# Repository Guidelines

## Project Structure & Module Organization

- `contracts/` contains the production Solidity sources, organized by AMM domain components.
- `script/` hosts Forge scripts (e.g., `DeployLocal.s.sol`) for seeding environments and running admin flows.
- `test/` holds Foundry suites; each `*.t.sol` mirrors a contract and keeps scenario helpers alongside assertions.
- `broadcast/` captures execution traces from `forge script --broadcast` runs, while `deployments/` tracks the latest resolved addresses.
- `var/` is the shared scratch space for agents; persist temporary state in `var/deployments/` or dedicated subfolders.

## Build, Test, and Development Commands

- `npm install` installs Hardhat-facing Node tooling required by the TypeScript config.
- `forge install` pulls Solidity dependencies declared in `foundry.toml` (e.g., `forge-std`, OpenZeppelin).
- `npx hardhat compile` compiles using the Hardhat pipeline and writes artifacts under `out/`.
- `forge build` performs a Foundry build, honoring `solc = 0.8.30`, `via-ir = true`, and optimizer settings.
- `forge script script/DeployLocal.s.sol --fork-url $RPC_URL --broadcast` deploys against a fork; produced artifacts land in `broadcast/` and `deployments/`.

## Coding Style & Naming Conventions

- Follow Solidity 0.8.30 style with 4-space indentation and explicit visibility; keep contract filenames PascalCase to match the primary contract.
- Prefer descriptive camelCase for functions/variables and ALL_CAPS for immutable configuration constants.
- Run `npx prettier --write "contracts/**/*.sol"` (configured with `prettier-plugin-solidity`) before committing; TypeScript utilities should also pass Prettier defaults.
- Align imports with `remappings.txt`; avoid relative paths that duplicate those entries.

## Testing Guidelines

- Use Forge for unit and integration tests: `forge test -vv` for verbose traces, or `forge test --match-test <Name>` to target a scenario.
- Keep test contracts under `test/` with the `ContractNameTest` pattern and initialize shared fixtures in `setUp`.
- Generate coverage via `npm run coverage`; review the resulting `lcov.info` and HTML report under `coverage/` to maintain meaningful branch coverage.
- Commit new edge-case tests alongside feature work, especially for liquidity math and fee boundaries.

## Commit & Pull Request Guidelines

- Write brief, present-tense commit subjects (e.g., `fix swap invariant`, `update liquidity math`), mirroring the existing history.
- Reference related issues or specs in the PR body, summarize behavior changes, and attach relevant `forge test` or script output.
- Confirm that migrations or deployment manifests in `deployments/` reflect the code being shipped and note any manual steps required for operators.

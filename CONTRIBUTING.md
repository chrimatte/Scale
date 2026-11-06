# Developing Scale

The main repository contains the macOS SwiftUI app, JavaScript helpers,
tests, scripts and assets. It does not embed the engine files: `ble-scale-sync`
is a Git reference to an upstream submodule,
initially pinned to commit `e2bb0666d47c9a546be454029329d5cb64d53a2b`
(version 1.39.1). The engine keeps its own history, remote and conventions;
setting up the main repository does not modify the engine.

## Git conventions

- Main branch: `main`; use short-lived branches named `feat/<topic>`,
  `fix/<topic>` or `chore/<topic>`. When collaborating, integrate through
  pull requests and review.
- Conventional Commits: `<type>(<optional scope>): <description>`.
  Common types: `feat`, `fix`, `docs`, `test`, `refactor`, `build`, `ci`, `chore`.
  Use `!` or the `BREAKING CHANGE:` footer for incompatible changes.
- Stage only reviewed paths. Check `git diff --cached` before committing;
  do not include profiles, API keys or weigh-ins.
- Submodule updates are explicit: review its changes and tests first,
  then record the new reference with `git add -- ble-scale-sync`
  in the main repository.

## Restoring a development checkout

You need macOS 14 or later on Apple Silicon, Apple Command Line Tools,
Python 3, npm and a Node version compatible with the engine manifest. The local
runtime is pinned by `work/runtime/package-lock.json`. From the root of a fresh checkout:

```sh
git submodule update --init
npm ci --prefix work/runtime
export PATH="$PWD/work/runtime/node_modules/.bin:$PATH"
npm ci --prefix ble-scale-sync
npm run build --prefix ble-scale-sync
cp -n Scale-sources/config.yaml.example ble-scale-sync/config.yaml
chmod 600 ble-scale-sync/config.yaml
```

The first submodule initialization downloads source files from the original
repository; ZIP archives generated from the main repository do not include them.
`npm ci` also downloads dependencies.
The repository does not contain credentials, your personal profile, weigh-in
state, backups or the compiled app. The starter configuration is fictional:
enter your profile in the app settings. Keep any backups of local data separately
and privately: Git does not replace them.

## Checks

From the root, using the available runtime:

```sh
work/runtime/node_modules/.bin/node --test Scale-sources/core.test.mjs Scale-sources/bridge.test.mjs Scale-sources/settings.test.mjs
(cd ble-scale-sync && ../work/runtime/node_modules/.bin/node node_modules/typescript/bin/tsc --noEmit)
zsh -n Scale-sources/build.sh Scale-sources/install.sh '1 - Connect Intervals.command' '2 - Start sync.command'
```

The app tests use fixtures and simulated connections. They do not upload weigh-ins.
For engine changes, also follow `ble-scale-sync/CONTRIBUTING.md`.
App build and installation are documented in `Scale-sources/README.md`;
the hook does not run them.

## Local hook

The lightweight check is `.githooks/pre-commit`: it requires Python 3 and Gitleaks
in `PATH`, checks whitespace and conflicts, exports the entire exact index to
a private temporary folder and scans it with Gitleaks. It then deletes the export;
it does not modify files or staging. It does not print sensitive values.

To enable it in a fresh checkout, first check `core.hooksPath` and any existing
hooks. If no other hook manager is configured:

```sh
git config --local core.hooksPath .githooks
```

Equivalent manual check, including before the first commit:

```sh
python3 .githooks/pre-commit
```

If Gitleaks is missing, the commit stops: make the scanner available before
retrying, without bypassing the hook. The check covers blobs in the main
repository; it does not scan ignored private files, archives or the engine's
history. Before publishing new commits, also check the history of the refs
to be uploaded.

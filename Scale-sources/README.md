# Scale for Mac — source and maintenance

A local SwiftUI app for recording a Renpho ES-CS20M weigh-in and syncing it with Intervals.icu. Requirements: Apple Silicon Mac, macOS 14 or later, Bluetooth and Internet access. The installed copy is `~/Applications/Scale.app`.

## Structure

The root folder contains `Scale-sources`, `Scale.app`, `ble-scale-sync` and `work` as sibling folders. Follow the [main README](../README.md) to prepare a fresh checkout.

The app reads `ScaleProjectRoot` from its `Info.plist`, set by `build.sh` to the current path of `ble-scale-sync`. It launches the local Node.js runtime at `work/runtime/node_modules/.bin/node` and the helper inside the bundle. The helper reads the configuration and starts the compiled engine in `ble-scale-sync/dist`.

The key stays in `ble-scale-sync/.env`, outside the bundle. The profile is in `ble-scale-sync/config.yaml`. Settings saves both with `0600` permissions after verifying the connection with a read-only request. The alternative launchers use the same data.

`work/mac-app` contains previous weigh-in state and temporary configuration. The temporary configuration is regenerated for each weigh-in, preserving duplicate-prevention markers.

## Build and installation

From the root folder:

```sh
./Scale-sources/build.sh
./Scale-sources/install.sh
```

The scripts also work when launched from another folder. `build.sh` builds in a temporary folder, signs and verifies the new bundle before replacing `Scale.app`, keeping a previous copy. It uses a virtual overlay to avoid a duplicate SwiftBridging module in some Command Line Tools installations, without modifying system tools.

`install.sh` requires Scale to be closed and a bundle built for the project's current location. It verifies the signature and updates `~/Applications/Scale.app`, keeping the previous version in `work/backups/install.*`. The app identity and icon remain `local.chrimatte.scale` and `AppIcon.icns`; the Dock continues to point to the installed copy.

After moving the entire project folder, run both scripts again from the new location. The previously installed version retains the path set during its build.

## Tests and local checks

From the root folder:

```sh
work/runtime/node_modules/.bin/node --test Scale-sources/core.test.mjs Scale-sources/bridge.test.mjs Scale-sources/settings.test.mjs
(cd ble-scale-sync && ../work/runtime/node_modules/.bin/node dist/index.js validate)
(cd ble-scale-sync && ../work/runtime/node_modules/.bin/node node_modules/typescript/bin/tsc --noEmit)
```

The tests use fictional data, simulated connections and temporary folders; they do not upload weigh-ins or modify the real profile. Fixture paths depend on the location of the test files rather than the working directory.

To rebuild the BLE engine with dependencies already installed:

```sh
(cd ble-scale-sync && ../work/runtime/node_modules/.bin/node node_modules/typescript/bin/tsc)
```

## Behavior to preserve

- Weight only by default; estimated body fat must be explicitly enabled.
- Existing body fat on Intervals.icu stays unchanged in weight-only mode.
- Final confirmation only after independently reading the saved values back.
- Stop terminates the reader process; completed uploads remain on the service.
- Settings cannot be changed during a weigh-in; a blank API key keeps the current one.
- No icon replacement while the app is running.

Simulations do not replace a physical weigh-in. Full light/dark appearance comparison and VoiceOver have not been verified.

# Scale for iPhone

Native SwiftUI app for iPhone running iOS 26.5 or later. The minimalist weigh-in
screen follows Scale for Mac. Bluetooth and HTTPS run on the phone; no Mac,
Node.js, Renpho account or intermediary server is needed during a weigh-in.

## Build and install

Open `Scale.xcodeproj` in Xcode 26.6 (iOS 26.5 SDK), select the Scale scheme,
choose your development team under Signing & Capabilities, and run on your
paired iPhone with Developer Mode enabled. The bundle identifier is
`local.chrimatte.scale.iphone`. Signing settings and credentials are not shared
in the repository. This is a development build, not an App Store release.

The committed project is generated from `project.yml`. After adding files or
changing build configuration, regenerate with `xcodegen generate` in this folder.

```sh
xcodebuild -project Scale-iOS/Scale.xcodeproj -scheme Scale \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath work/ios-build CODE_SIGNING_ALLOWED=NO test
```

## First weigh-in

1. Close Renpho and stop Scale on the Mac so they do not compete for Bluetooth.
2. Tap Start weigh-in, wake the scale and select it from the nearby list.
3. Wait for Scale connected, then step on and stand still with Scale open.
4. A stable reading is saved on the iPhone. The app asks
   **“Vuoi condividere il peso su Intervals?”**. **Condividi** uploads it;
   **Non ora** keeps it locally without contacting Intervals.icu.
5. To share later, tap Share with Intervals.icu and confirm. If the connection
   has not been configured, enter the athlete ID and API key in Settings,
   save and verify, then return and explicitly share again. Weighing itself
   does not require an Intervals account or Internet access.

Weight is sent after explicit confirmation. Enable **Include estimated body fat**
in Settings before a new weigh-in to save and share an estimated percentage too.
Set height, age and sex correctly: the adult Deurenberg estimate uses these values
and weight, and is not the value measured by Renpho. It is shown on the weigh-in
screen and in the sharing confirmation, rounded to one decimal place. The option
is off by default. Saved readings retain their original estimate across settings
changes, relaunch and retries. Without an estimate, existing body fat is unchanged. Further shared weigh-ins on the same athlete calendar day
replace that day's weight. Success is shown only after independent readback.
A failed upload stays on the phone; retry requires another explicit confirmation.
The original measurement date is retained. Retry can repeat an upload that
reached the server before its response was lost. There is no automatic upload
on capture, relaunch, settings save, or app foreground/background transitions.
Only one unshared reading is retained. New weigh-in replaces it, as stated next
to the button. A reading with no account configured is bound to the athlete on
explicit sharing; an already-bound reading cannot be redirected to another
athlete. This prevents an accidental account change from moving a saved weight.

Leaving the app during a weigh-in stops scanning/upload work and retains any
pending weight. An in-flight request may already have updated Intervals.icu.
Bluetooth access is requested only when starting a weigh-in.

## How estimated body fat is calculated

The optional iPhone estimate uses the measured weight and the height, age and sex
entered in **Settings → Scale profile**. It applies the adult Deurenberg formula:

```text
BMI = weight in kg / (height in metres)²
Body fat (%) = 1.20 × BMI + 0.23 × age − 10.8 × sex − 5.4
```

Here, age is in years and the formula’s sex coefficient is 1 for Male and 0 for
Female. The iPhone implementation accepts ages 18–100 and heights 100–230 cm,
clamps the result to 3–60%, and rounds it to one decimal place before saving and
sharing it. These bounds are implementation limits, not a statement of accuracy.
No athlete adjustment is applied.

This is a formula-based estimate: **it does not use electrical impedance from the
scale and does not read the body-fat percentage calculated by Renpho**. It can
differ from the Renpho app’s value. An incorrect profile also changes the estimate.
The calculation is implemented in `Sources/ScaleProtocol.swift`, following the
adult Deurenberg fallback in the pinned ble-scale-sync source.

## Bluetooth scope and validation

Discovery recognizes ES-CS20M/ESCS20M, QN-Scale, Renpho, ES-32MD and
113360-prefixed names, full or short service UUIDs, and supported anonymous
advertisements. Separate advertisements from the same peripheral are merged;
a name-only candidate can become a broadcast scale when its payload arrives.
Selection waits briefly for broadcast evidence before attempting a connection.
Unknown unnamed Bluetooth accessories are not labeled as Renpho scales.
The app now waits for subscription before asking you to step on the connected
scale. Live validated weight frames are displayed while settling, but only a
final reading is uploaded. Legacy ES-CS20M commands prefer write-without-response,
matching the Mac engine; the guest handshake is selected by AE01/AE02
characteristics rather than the service name alone. Split/coalesced notifications
are reassembled with length and checksum validation.

Connection details can be expanded during or after a failed attempt. They show
connection stages, service/characteristic UUIDs, and the length/first three bytes
of the first five notifications; no API key or complete measurement packets are
logged. Details are kept in memory and cleared on the next attempt. A connection
that never completes times out after 20 seconds.

A timeout reports nearby-device and candidate counts to distinguish scanning
problems from recognition or measurement problems.

Implemented from the pinned GPL-3.0 ble-scale-sync protocol sources:

- QN AABB broadcast readings under manufacturer ID `0xFFFF`, stable flag required.
- ES-CS20M `1A10`, notify `2A10`, write `2A11`, including the AE00 revision's
  guest-slot handshake. No registered user slots are deleted or overwritten.
- Live stable `0x14` readings and a live weight followed by power-off. Stored
  offline records are ignored. Frame lengths, checksums and weight bounds are
  validated before accepting connected readings.

Other connected QN dialects (FFE0/FFF0), historical imports and native Renpho body
fat are not implemented in this first iPhone version. Unsupported characteristic
layouts produce an explicit message. Bluetooth needs a real device: simulator
success does not establish compatibility with a physical Renpho revision.
The guest handshake and anonymous-device discovery still need hardware validation.

Tests cover packet validation, stability, stored-record exclusion, power-off
fallback, athlete time zones, weight-only and body-fat HTTP payloads, estimate persistence, independent readback,
readback mismatch, capture/relaunch without upload, explicit sharing, failed sharing without automatic retry, and home/settings/sharing navigation. HTTP tests use synthetic data
and never contact Intervals.icu. Manual hardware acceptance: compare the stable
weight against the scale display, verify the correct daily Intervals record,
repeat after cancellation, test Bluetooth denial/off, and retry after a network
failure. VoiceOver and physical Bluetooth remain manual checks.

## Data and credits

The API key lives in this device's Keychain with unlocked-device access. Profile
preferences are local. One pending weigh-in is stored with complete file
protection and excluded from backup, then removed after successful verification.
Only requested account/measurement traffic goes to Intervals.icu. No telemetry or
analytics SDKs are included. No credentials are imported from the Mac.

Protocol attribution: KristianP26/ble-scale-sync, pinned by the repository's
submodule, especially `src/scales/qn-scale/broadcast.ts`, `es-cs20m.ts`, and
`renpho-55aa.ts`. The iPhone sources are covered by the repository's GPL-3.0-only
license. The app icon reuses Scale's existing artwork.

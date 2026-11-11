# ADI-2 Companion for macOS

A native SwiftUI controller and offline EQ editor for RME ADI-2 DAC hardware.
The Mac app uses CoreMIDI and the same published RME
SysEx protocol as this repository's Linux app. It has no GTK, Python, ALSA,
network service, driver installer, or administrator requirement.

This is independent software, not affiliated with or endorsed by RME.

## Current scope

The first paid Mac release is being prepared as version 1.0.0, build 2. This
scope change has not yet been built, signed, uploaded or hardware-qualified.
Build 1 was delivered, processed and attached to the App Store Connect draft;
no version has been submitted to App Review or publicly released.

- A main volume fader that smoothly follows hardware knob updates, with direct
  0.1 dB input and Reduce Motion support.
- Five-band EQ with a combined response curve, numeric controls,
  and per-output draft editing.
- Explicit connection and state synchronization through USB MIDI. Hardware
  writes stay disabled until a compatible device returns its EQ state.
- Apply a reviewed EQ draft to both channels of the selected output.
- Parameter controls for output and device settings, including channel EQ/tone
  parameters. These controls write immediately when
  connected; the separate EQ band editor uses the explicit Apply action.
- Import Equalizer APO/REW filter text, CSV filter data, and compatible JSON.
  Import warnings describe adjustments to the hardware's five-band limits.
- Export a local JSON EQ profile through the macOS file picker.
- Save and load profiles in a local library inside the app's sandbox.
- A clearly marked demo mode that sends no MIDI, with an original **Example EQ**
  for exploring the editor. It is illustrative, not a headphone-specific
  correction or listening recommendation.

The macOS app does not apply the Linux PipeWire configuration, manage macOS
audio routing, or change the system sample rate. No audio is captured or
processed by this app; the ADI-2 performs its DSP.

## Requirements and connection

- macOS 14 or later.
- An ADI-2 with firmware supporting RME's MIDI control protocol, connected by USB.
- Enable **MIDI Control** on the hardware. RME's current Remote manual names
  **Remap Keys/Diag** for the DAC; menu wording can vary with firmware.

The recorded DAC checks include USB 80 / DSP 55 and USB 81 / DSP 62 firmware.
Pro/2/4 model code remains in the repository, but those models have not been
qualified with this Mac app and are outside the first paid listing's claims.

Choose the device in the sidebar, then click **Connect**. The app reads its
current state before enabling writes. **Sync** reads settings again after a
front-panel change. Disconnecting does not reset the hardware. Closing the app
leaves the ADI-2's settings in place.

The main volume fader draws its track, fill, and knob with Core Animation layers.
Incoming device values retarget a 0.18-second ease-out from the knob's current
visible position, including when a new report arrives before the previous move
finishes. A grabbed thumb starts a drag from the actual volume, even mid-animation.
Pointer dragging stays immediate; keyboard and accessibility controls
use the authoritative device value in 0.1 dB steps. Reduce Motion, a disabled
control, or an output/connection change snaps directly to the target. Animation
never sends interpolated MIDI values.

A read-only live observation captured 86 physical-knob reports with a typical
64.3 ms interval. The renderer smooths the main fader between incoming reports;
it does not change that device cadence. The user tested the new universal build
with the physical DAC knob and confirmed smooth feedback. This acceptance covers
the observed DAC workflow, not Pro/2/4 hardware or other release checks.

EQ imports create drafts. Review the curve, band values, and import warnings,
then choose **Apply EQ to Both Channels**. Imported preamp gain has no direct
ADI-2 equivalent; heed the reported warning and adjust output volume separately.
Use an appropriate listening level before changing gain or output settings.

Without hardware, choose **Explore demo**, or import and edit a profile offline.
Leaving demo clears simulated settings. Demo is not a hardware validation.

## Local profiles

Open **Local profiles** in the sidebar. Local profiles belong to
this Mac app's sandboxed Application Support library (`ADI2Companion/Profiles`).
Loading a local profile creates an EQ draft; it does not send MIDI. Use Export
to save a copy outside the library or share it with another machine. Library
profiles remain in the app's sandbox until its app data is removed. Exported
copies and hardware settings are independent of that app data.

## Build a local development app

The command-line build needs Apple's Swift toolchain and macOS SDK, available
through Xcode or the Command Line Tools. The XCTest suite additionally needs
full Xcode. From this directory:

```sh
swift test                 # requires full Xcode's XCTest framework
./scripts/build-app.sh
open "build/ADI-2 Companion.app"
```

With Command Line Tools alone, run `./scripts/test-cli.sh`. It compiles the core
and connection-state test bodies with standalone assertion runners when XCTest
is unavailable. On a toolchain exposing XCTest, it uses `swift test` instead.
These tests use fake MIDI and do not verify physical device communication.

The delivered build 1 baseline passed 50 core/model cases with 323 assertions:
33 core cases with 205 assertions and 17 app-model cases with 118 assertions.
A separate isolated fader suite passes 10 cases with 48 assertions. It samples
actual presentation-layer positions across display frames, including rapid
retargeting and reversal, immediate direct input, 0.1 dB keyboard/accessibility
steps, Reduce Motion, disabled controls, and zero input callbacks from animation.
The prior sandboxed universal app built for Apple silicon and Intel. These
results remain historical evidence for build 1 and the unchanged fader.

The build 2 scope patch passed the existing CLI harness: **51 cases, 342
assertions, zero failures** (core 33/205; app model 18/137). It retains the 17
prior model cases and adds a fake-MIDI regression for blocked device-memory
operations and preserved live/local workflows. The app archive, signature,
upload and build 2 runtime qualification remain pending.

The native sandboxed app has been tested with a physical **ADI-2 DAC on Apple
silicon, macOS 27.2**. USB MIDI discovery, a complete 219-parameter settings
read, and a GUI Phones volume reduction of 0.1 dB followed by restoration all
passed, with a fresh hardware Sync confirming each volume step. The final
distribution-signed build 1 also passed a neutral EQ Apply and fresh readback.
See [the hardware record](HARDWARE_TESTING.md) for scope and limitations.

Pro/2/4 models, unplug/replug, Intel runtime behavior and other supported OS
versions remain unqualified. Build 1 has a verified Xcode archive, distribution
signature and accepted upload; build 2 still needs its own build, validation
and runtime evidence.

To open the demo directly:

```sh
open "build/ADI-2 Companion.app" --args --demo
```

The script builds a release executable, creates a self-contained app bundle,
copies the icon, license, and privacy manifest, then signs it ad hoc with App
Sandbox enabled. It checks the signature, required bundle files, entitlements,
and quarantine attributes. This is a development app for this Mac, not an Apple
distribution-signed or notarized release.

To build both Apple silicon and Intel slices:

```sh
./scripts/build-app.sh --universal
```

To choose an output directory:

```sh
./scripts/build-app.sh --output /absolute/path/to/output
```

## Check fader motion with Command Line Tools

The motion harness needs a logged-in graphical Mac session. With Command Line
Tools installed, run these commands from `macOS` in a GUI terminal:

```sh
mkdir -p .build/fader-check-realtime
DEVELOPER_DIR=/Library/Developer/CommandLineTools xcrun swiftc -parse-as-library -D REALTIME \
  Sources/ADI2Mac/VolumeFader.swift Tests/ADI2MacTests/VolumeFaderTests.swift \
  -o .build/fader-check-realtime/VolumeFaderCheck
.build/fader-check-realtime/VolumeFaderCheck --report "$PWD/.build/fader-check-realtime/results.json"
```

`-D REALTIME` selects the visible wall-clock acceptance probe. Omit that flag
and choose a separate output/report path to run the controlled Core Animation
clock used by CI. Both modes run the same 10 cases and 48 assertions; only the
test clock changes. Controlled mode samples actual presentation geometry at
known CA times and does not claim a real-time frame rate. Reports identify the
mode and include bounded CA/wall timestamps and positions for motion checks.

Click **Run self-check**. The window reports cases, assertions, failures, and
sampled positions; the JSON report is written after the checks finish. This app
compiles only the fader component and its tests: it does not construct the app
model, open CoreMIDI, or contact hardware. The existing `test-cli.sh` runs the
core/model checks separately. Full Xcode discovers the component cases through
`swift test`; meaningful motion evidence still requires real window compositing.

## Xcode and App Store preparation

Open `ADI2Companion.xcodeproj` in full Xcode. The shared **ADI2Companion** scheme
builds the SwiftUI app and the local Swift package's `ADI2Core` library. The
project has an app icon, privacy manifest, bundle identifier, version/build
number, and sandbox entitlements checked in; it needs no project generator.

Select your Apple Developer team in Signing & Capabilities. Confirm that the
bundle identifier `tech.norvi.ADI2Companion` is available for that team before
registering it. Use Product → Archive, validate the archive, and distribute via
TestFlight & App Store. An Apple account, signing assets, App Store Connect
record, and complete review metadata are required.

See [App Store preparation](APP_STORE.md) for the remaining release work and
current Apple source links. The build 1 archive/signing/upload evidence does
not validate build 2 or establish Pro/2/4 compatibility.

## Protocol reference

The authoritative reference is RME's
[MIDI protocol download](https://www.rme-audio.de/downloads/adi2remote_midi_protocol.zip),
linked from its [ADI-2 Remote manual](https://rme-audio.de/downloads/adi2remote_e.pdf).
The archive contains `MIDITable_ADI-2_261030.ods`, version 1.2, dated
October 30, 2026; its stated firmware bases are Pro 130, DAC 62, 2/4 SE 43,
and 2/4 EX 106.

In the `Channels` sheet, EQ Enable (index 2, row 80), Bass/Treble (indices
20–26, rows 99–106), and preset behavior (indices 27–28, rows 107–110) are shared
controls on the documented left EQ addresses. Bilateral band controls use
indices 3–19. The official examples and the live DAC settings dump also report
index 2 on right EQ addresses; the app accepts that incoming state without
requiring it or sending a right-side enable/tone/preset write. Live EQ/tone
switches are written once at their documented left address. Preset behavior
controls retained internally are outside this release's scope.

## Source layout

| Path | Purpose |
| --- | --- |
| `Sources/ADI2Core` | SysEx protocol, parameter registry, profiles, imports, EQ response |
| `Sources/ADI2Mac` | SwiftUI app, local CoreMIDI transport, file pickers |
| `Tests` | Protocol, import, library, and fake-MIDI connection-state tests |
| `Resources` | App metadata, sandbox entitlements, privacy manifest, original icon |
| `scripts` | Development bundle build, verification, icon rendering |

To regenerate the original icon artwork:

```sh
swift scripts/render-icon.swift
iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
```

## Privacy, support, and credits

The app has no network entitlement, accounts, advertising, or telemetry.
Import/export uses the file picker; library profiles stay inside the app's
sandbox. See the
[privacy policy](PRIVACY.md). Report reproducible problems through this
repository's [issue tracker](https://github.com/spencernorton/rme-adi2-linux/issues),
including macOS version, Mac architecture, ADI-2 model/firmware, and steps.
Do not include personal files or sensitive diagnostic data.

Code is MIT licensed; the bundled license preserves the copyright notice.
RME's published MIDITable is the protocol reference. The Mac app's bundled
**Example EQ** uses original, gentle settings to demonstrate the editor rather
than a third-party headphone correction. Imported and saved profiles retain the
shared JSON format. All product names identify compatible hardware and remain
their owners' property.

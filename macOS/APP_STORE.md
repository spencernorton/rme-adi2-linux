# Mac App Store preparation

The first paid Mac release is scoped to live ADI-2 DAC control, offline EQ
editing, and local profiles. Build 2 is a prepared scope change, not a built,
signed, uploaded or hardware-qualified release.

Version 1.0.0 build 1 was delivered through Apple's Transporter app, processed,
and attached to the App Store Connect version draft. Two screenshots and a
physical-camera hardware video have been uploaded. No App Review submission or
public release has occurred. Build 1's acceptance does not validate build 2.

The baseline source is public after PR 1 merged as
`9ef636f07a00a07a3e9d3deff5dd972eaa0996ee`. Anonymous checks at
19:25:27 UTC on November 11 confirmed HTTP 200 for the GitHub HTML and raw
support, privacy and Mac README pages, with raw bytes matching `dfade65`.
This first-release scope follow-up remains unpublished; reverify its updated
pages after merge.

## First-release scope

- Native SwiftUI app using public CoreMIDI, AppKit, and Foundation APIs; macOS 14+.
- Five-band EQ drafts, response graph, import warnings, and explicit Apply.
- Live volume and non-memory output/device parameter controls.
- Offline editing, file-picker import/export, and a sandboxed local profile library.
- Clearly identified demo mode without MIDI writes.
- Original artwork, Music category, no accounts, ads, telemetry or audio recording.
- App Sandbox and user-selected file read/write entitlements only.

Persistent device EQ/setup storage, naming and recall are excluded from this
Mac release. The proposed immutable capability is off: the UI omits these
operations, memory-related generic controls are filtered, and model entry
points reject calls. Internal protocol code and explicit opt-in tests remain
for development; the Linux app is unchanged. There is no user enable switch.
Do not advertise device memory or include it as an optional paid feature.

The source configuration targets version 1.0.0 / build 2. This document does not
assert a successful app build, archive, signature or upload for that change.

## Recorded evidence

- **Build 1 archive:** [CI run 43042638214](https://github.com/NorviTechGH/rme-adi2-linux/actions/runs/43042638214)
  at `ec848fcdf4f1aea7a2b38758441141eb53e01257` produced the actual universal
  Xcode archive with Xcode 16.4 (16F6), macOS SDK 15.5 (24F74), and deployment
  target 14.0 in both arm64 and x86_64 slices. Artifact digests, payload hashes,
  app/archive equality, dSYM UUIDs, resources and entitlements were checked.
- **Build 1 distribution:** A fresh archive copy was signed and packaged using
  genuine Mac App Store application/installer identities. Local checks covered
  signatures, both slices, exact entitlements, resource and executable
  equivalence, and the expanded single-app package without installer scripts.
  Transporter subsequently delivered the package and App Store Connect made
  build 1 available for selection. Warning ITMS-90889 concerns TestFlight's
  missing provisioning profile, not direct Mac App Store eligibility.
- **Prior software evidence:** The delivered baseline passed 50 core/model
  cases / 323 assertions. The isolated fader harness passed 10 cases / 48
  assertions. These are historical results, not results for the scope patch.
  Controlled Core Animation samples establish interpolation semantics, not a
  real-time frame-rate guarantee; a separate visible REALTIME replay was used.
- **Scope-patch software checks:** The existing CLI harness passed 51 cases /
  342 assertions, zero failures: core 33/205 and app model 18/137. The new model
  case covers the default memory block and retained live/local workflows with
  fake MIDI. These results do not establish a build 2 archive or hardware pass.
- **Physical DAC:** On Apple silicon with macOS 27.2, the sandboxed app completed
  MIDI discovery and fresh 219-parameter synchronization. A 0.1 dB Phones-volume
  reduction/restoration passed fresh readback; the owner confirmed smooth
  physical-knob feedback. Distribution-signed build 1 also passed a neutral EQ
  Apply followed by fresh hardware readback.
- **Memory failure and scope:** Bounded checks returned the saved EQ bands but
  failed the preset-name round trip on DAC USB 80 / DSP 55 and again on USB 81 /
  DSP 62 through the full save/name path. An isolated name-only attempt after
  the commit settled failed on USB 80 / DSP 55 only.
  The cause is unproven. This does not justify changing the documented commit
  address or guessing a new name encoding. See [the hardware record](HARDWARE_TESTING.md).
- **Review assets:** Two genuine 2880×1800 screenshots from an isolated demo
  capture copy and a physical-camera Mac/DAC interaction video are attached to
  the version draft. Check their visible UI and scope against the final build 2;
  their presence is not App Review approval.

Pro/2/4 hardware, Intel runtime behavior, other OS versions and unplug/replug
remain unqualified. The existing checks do not establish every parameter or
arbitrary EQ transition. Do not turn the neutral Apply result into a broader
hardware claim.

## Remaining release gates

1. **Review the scope patch.** Verify that device memory is unavailable through
   both the visible interface and model calls, including generic controls that
   select presets or configure memory behavior. Retain local profiles and live
   EQ/volume/non-memory parameter controls. The CLI checks passed as recorded
   above; confirm the exact committed head through native CI and inspect its
   resulting archive.
2. **Build and validate build 2.** Produce a new universal Xcode archive and
   provenance receipt, then sign and package a fresh copy. Check its runtime
   behavior and exact entitlements. Build 1's evidence does not automatically
   transfer to the changed binary.
3. **Deliver and select build 2.** Verify Apple's acceptance and processing, and
   replace build 1 in the version draft only with the actual processed build 2.
   Keep signing keys local and out of CI. Do not create a provisioning profile
   solely to address the TestFlight warning when submitting directly to the
   Mac App Store with only unrestricted entitlements.
4. **Reconcile assets and metadata.** Check the existing screenshots/video against
   the final UI. Use the local-profile sidebar and omit device-memory offers.
   Complete any remaining review/contact, privacy, age-rating, export-compliance,
   storefront and trader fields against the shipping binary, and reverify the
   updated public pages after this follow-up merges. The baseline support,
   privacy and README URLs are already verified live. Keep private account/contact details
   in App Store Connect.
5. **Submit only the finished scope.** Describe the exact tested DAC/firmware,
   Mac/OS and app revision in review notes. Confirm the USD 15.00 upfront price,
   territories, product identity, rights and support arrangements. No App Review
   submission or public release is implied by this preparation.

## Build and signing workflow

With full Xcode selected, run `swift test` from this directory. Command Line
Tools alone lack the XCTest framework; `./scripts/test-cli.sh` provides the
standalone core/model harness. Software tests use fake MIDI. The isolated fader
harness is documented in [README.md](README.md).

Open `ADI2Companion.xcodeproj`, select the intended team and the shared
**ADI2Companion** scheme, and archive a Mac destination. Version, build and
bundle identifier come from `Resources/App.xcconfig`. Use a new build number
for each new upload.

The build 1 workflow used a verified unsigned CI archive and local manual
signing plus `productbuild`, followed by Transporter. That route is supported
by Apple's [signing](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac),
[packaging](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution)
and [Transporter](https://support.apple.com/guide/transporter-app/welcome/mac)
documentation. Preserve the original archive and receipt and sign a copy.
`./scripts/build-app.sh --universal` creates a development bundle; that alone
is not a distribution archive, accepted upload or hardware qualification.

Verify the final bundle with `scripts/verify-app.sh /path/to/ADI2Companion.app`
and separately verify the actual distribution identities and installer chain.
TestFlight requires a provisioning profile even though a Mac App Store app
with only unrestricted entitlements need not have one. See [Apple DTS](https://developer.apple.com/forums/thread/733942)
and [TN3125](https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles).

## Metadata draft

Concrete English (US) strings and status are in
[AppStore/metadata-en-US.json](AppStore/metadata-en-US.json). They describe the
planned build 2 scope and must not be presented as the already uploaded build 1.

| Field | Prepared value |
| --- | --- |
| Name | ADI-2 Companion |
| Subtitle | Parametric EQ and MIDI control |
| Primary category | Music |
| Bundle ID | `tech.norvi.ADI2Companion` |
| Version / planned build | 1.0.0 / 2 |
| Base price | USD 15.00 upfront, one time; no in-app purchases or subscriptions |
| Support URL | https://github.com/spencernorton/rme-adi2-linux/blob/main/macOS/SUPPORT.md |
| Privacy URL | https://github.com/spencernorton/rme-adi2-linux/blob/main/macOS/PRIVACY.md |
| Marketing URL | https://github.com/spencernorton/rme-adi2-linux/blob/main/macOS/README.md |

The listing covers five-band drafts, response graphs, imports with warnings,
local profiles, offline/demo use, and live DAC EQ/volume controls. It does not
promise Pro/2/4 compatibility. Use original artwork and no RME logo or claim of
affiliation. Review notes must identify the hardware requirement and exact
setup steps, including that live parameter controls write immediately while EQ
band edits require Apply. Local-profile loads create drafts without MIDI.

## Screenshots, hardware video and privacy

Mac screenshots must be opaque, 16:10 PNG/JPEG at 1280×800, 1440×900,
2560×1600 or 2880×1800; at least one is required. Retain the demo banner for
simulated states. Do not mask old controls or invent a live connection to make
an image match a changed app. See the [capture guide](AppStore/screenshots.md).

Apple requires a physical-camera video, not a screen recording, showing the
app on a physical Mac connecting to and interacting with the DAC. The existing
build 1 video is uploaded; reconcile it with the submitted build and include
tested device/OS information. [Complete review requirements](https://developer.apple.com/help/app-review/before-submitting-for-review/complete-review/)

The app declares no tracking, data collection or required-reason API use in its
privacy manifest. Retain the corresponding privacy answers only if the final
binary and dependencies match. Check the live policy/support links and actual
contact mechanism. Existing keyboard/VoiceOver component checks alone do not
establish a complete Accessibility Nutrition Label assessment.

## RME protocol reference

RME's [official protocol archive](https://www.rme-audio.de/downloads/adi2remote_midi_protocol.zip)
is linked from the [Remote manual](https://rme-audio.de/downloads/adi2remote_e.pdf),
page 3. `MIDITable_ADI-2_261030.ods` is version 1.2, October 30, 2026, with
stated firmware bases Pro 130, DAC 62, 2/4 SE 43 and 2/4 EX 106. These table
bases are not a measurement of a connected device's firmware.

The `Channels` sheet documents left-address EQ Enable index 2 (`A80:G80`),
Bass/Treble indices 20–26 (`G99`, `A100:B106`), and preset behavior indices
27–28 (`G107`, `A108:H110`). Band indices 3–19 are bilateral. Optional incoming
right-side EQ enable does not expand the write contract. Preset behavior and
persistent-memory APIs retained internally are excluded from the release scope.

## Apple references checked November 10–11, 2026

- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/):
  sandboxing, public APIs, self-contained packaging, privacy and rights.
- [App Sandbox](https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox):
  no speculative MIDI, broad USB, audio or network entitlement is needed here.
- [Upload builds](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/):
  the current macOS table permits builds made with Xcode 6+ and uploads through
  Xcode 14+; mobile SDK minimums are a separate requirement.
- [Upcoming requirements](https://developer.apple.com/news/upcoming-requirements/):
  submission changes, including quarantine attributes.
- [Privacy manifests](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files)
  and [required-reason APIs](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api).
- [Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/).

Recheck current Apple requirements before submission. Accepted processing does
not guarantee review or release approval.

## 2026-11-11 — Prepare the first Store release without device memory

- The isolated settled name-only attempt failed on DAC USB 80 / DSP 55, and the
  full save/name path failed again on USB 81 / DSP 62 after the update. The
  first paid Store release therefore excludes persistent hardware
  EQ/setup save, recall and naming controls. No alternate encoding or further
  hardware experiment is inferred from the unresolved protocol behavior.
- Added an immutable, default-off Mac release capability. The device-memory
  sections and confirmations are absent, generic preset/recall-key controls are
  filtered, and model dispatch rejects those operations before MIDI. Local
  profiles, import/export, offline drafts and live EQ/volume controls remain.
  Internal protocol/model coverage opts in explicitly through fake transports;
  the Linux app and shared profile format are unchanged.
- Preserved all 17 model cases and added one additional fake-MIDI regression
  covering valid-but-blocked memory operations, generic-selector bypass attempts,
  retained live control and local profiles. After source review, the existing
  CLI harness passed 51 cases / 342 assertions, zero failures (core 33/205;
  app model 18/137). No app build, signing, upload or publication was performed
  for this candidate before that software check.
- Updated Mac help/listing scope and prepared version 1.0.0 / build 2. The
  delivered build 1 and its historical evidence remain distinct: root verified
  neutral EQ Apply and a fresh 219-parameter readback, but this does not establish
  physical qualification of the unbuilt build 2. The DAC has been released.
- Next: review this isolated follow-up, place only its approved commit on the
  actual squashed main, run native CI, and validate a fresh build 2 and
  matching review assets. No future memory feature or App Store release is
  promised by this preparation.

## 2026-11-11 — Separate fader CI timing from real-time acceptance

- Hosted run 43051754638 at the documentation-only `f8a2a35` head passed all
  50 core/model cases and nine fader cases, but failed the first post-retarget
  wall-clock sample's proximity assertion. That case took 2.233 seconds despite
  approximately 0.423 seconds of requested sleeps. The log lacked retarget
  geometry, so it did not establish a production renderer jump; it exposed the
  remaining test's dependence on hosted scheduling.
- Routed all six scene-based timing checks through one test clock. CI steps
  actual presentation layers on a controlled Core Animation timeline;
  `-D REALTIME` changes only that helper to wall-clock progression for visible
  local acceptance. Both modes run identical case bodies, all 10 cases and
  48 assertions, with unchanged numerical thresholds and no skips. Bounded
  diagnostics identify the mode and record CA/wall timestamps and geometry.
- Both fresh isolated preview apps were visibly launched and checked locally:
  controlled mode and REALTIME each passed 10 cases / 48 assertions with zero
  failures. Their JSON reports confirm the modes and actual intermediate
  presentation samples, retarget continuity and authoritative drag baseline.
  Controlled CI samples establish interpolation semantics, not a real-time FPS
  guarantee; the separate REALTIME replay supplies the wall-clock probe.
- Updated the documented harness command for explicit REALTIME mode. Production
  sources/resources remain identical to the distribution-signed `ec848fc`
  baseline; app animation duration, MIDI behavior and packaging are unchanged.
  No hardware action was performed by these component checks.

## 2026-11-11 — Verify the Xcode release archive and capture provenance

- Native and Linux CI passed at
  `ec848fcdf4f1aea7a2b38758441141eb53e01257`
  ([run 43042638214](https://github.com/NorviTechGH/rme-adi2-linux/actions/runs/43042638214)).
  Downloaded and independently verified the actual unsigned universal Xcode
  app/archive: GitHub artifact digest, all payload checksums, source receipt,
  identical app/archive files, matching dSYM UUIDs, privacy/license resources,
  icon renditions and supplied sandbox entitlements. Xcode 16.4 (16F6) produced
  SDK 15.5 (24F74) / minimum macOS 14.0 in both arm64 and x86_64 slices.
- Core/model checks pass 50 cases / 323 assertions. The isolated fader suite
  passes 10 cases / 48 assertions in native CI and a visible local replay.
  Interpolation and burst cases sample actual presentation layers on a controlled
  Core Animation clock; they establish intermediate geometry and callback
  separation, not a real-time frame-rate guarantee. Independent real-time
  retarget and authoritative mid-animation drag checks remain. Production
  animation behavior is unchanged.
- Captured and attached two genuine 2880×1800 screenshots to the version draft
  using an isolated demo copy of the verified revision. The only source
  difference is the default window size (1120×800 to 1440×900), with an
  independent capture bundle/sandbox.
  Capture provenance does not qualify hardware or the final signed binary.
- Signed a fresh archive copy with genuine Mac App Store application/installer
  identities and produced an upload package. Verified both architectures,
  exact sandbox entitlements, certificate identities, preserved executable
  payload after narrowly audited signing metadata changes, and identical
  expanded package contents without installer scripts. Keys remain outside CI.
  Transporter acceptance, final runtime qualification and App Review remain
  open. The version draft retains the selected USD 15.00 upfront base price.
- No persistent EQ/setup memory write has been performed. Read-only preset
  replies use a different flags index from the documented staging/commit
  control; incoming reports alone do not establish a different write address.
  Qualify the documented write sequence in a reserved unused slot with fresh
  readback and volume protection. EQ Apply, memory, reconnect, Pro/2/4 and Intel
  runtime qualification remain open for the final signed build.
- Updated `macOS/APP_STORE.md` to distinguish completed archive/capture/signing
  work from final hardware/video qualification, public URL/metadata,
  Transporter processing and review gates. No production source or tests changed.

## 2026-11-11 — Route native CI around hosted runner capacity

- Fork workflow run 43032041326 at `a8b8210` passed Linux regression, but GitHub
  cancelled the native job before any step ran: no hosted runner was acquired,
  with an explicit macOS arm64 capacity notice. This was not a compiler or test
  failure, and it produced no new native/archive validation evidence.
- Selected the standard `macos-15-intel` hosted runner documented by
  [GitHub](https://docs.github.com/en/actions/reference/runners/github-hosted-runners).
  Generic Mac archive destination and both `arm64` / `x86_64` builds remain
  required. No larger runner, signing credentials or runtime permissions added.
- Validation: workflow YAML parses and the diff is clean. Next: rerun CI on the
  new head and retain the verified Xcode archive before local distribution signing.

## 2026-11-11 — Resolve native CI compiler compatibility

- The first full-Xcode runner found ambiguous channel-index type inference and
  an EQ Canvas expression exceeding its type-checking budget before tests ran.
- Made the index collection explicitly typed and split graph drawing/dragging
  into small typed helpers. Geometry, drawing order, draft behavior and MIDI
  dispatch are unchanged; no hardware action or app restart was performed.
- Validation: 50 core/model cases / 323 assertions and universal development
  compilation pass locally. The next CI run must validate the older Xcode
  compiler and actual Xcode archive; this is not an App Store validation claim.
- Next: finish native CI and physical memory qualification, keeping the release
  PR as work in progress until the remaining release evidence is complete.

## 2026-11-11 — Use an original Mac example profile for release

- Replaced the Mac app's bundled DT 1990 reference with an original, gentle
  **Example EQ** for illustrating the editor. The previous five-band adaptation's
  exact upstream source/revision and commercial-use provenance were unresolved;
  this change makes no claim about infringement. The example is not marketed as
  a headphone-specific correction or listening recommendation.
- Demo state and its simulated first preset now use the example. Selecting it
  creates a draft for the chosen output; it never applies EQ automatically.
  Flat EQ, imports, the shared JSON schema, saved profiles and the Linux legacy
  source/data are unchanged. No migration or replacement of user profiles occurs.
- Updated Mac importer/library/preset test fixtures to the original example. The
  preset byte oracle was generated independently with the unchanged Linux
  encoder and the new illustrative numbers. Core/model CLT checks pass:
  33 core cases / 205 assertions and 17 fake-MIDI app cases / 118 assertions.
- Release Help now targets the prepared support page, and the privacy alert's
  paragraphs use real newlines. The accepted main-fader renderer is unchanged.
  The running app, connected DAC and pending personal EQ draft were not changed,
  restarted or applied by these source/test edits.
- Next: run native CI on this release source, prepare fresh capture assets from
  its resulting build, and publish the support/privacy pages through the source
  PR before using their URLs in App Store Connect.

## 2026-11-11 — Prepare the paid Mac App Store release

- Created the intended app record and explicit bundle identifier after the user
  completed Apple's updated Developer Program License Agreement. Saved the
  English (US) version draft and the requested USD 15.00 upfront base price.
  The paid agreement/compliance, signed upload and App Review remain pending.
- Added listing/review drafts, genuine screenshot capture preparation, synthetic
  fixtures and a public maintainer support page. Canonical URLs still need the
  source PR to land before they can be used in the submitted listing.
- Added a CI path retaining the actual unsigned universal Xcode archive/app,
  sandbox entitlements and a source/SDK/symbol-bound checksum receipt. Apple
  signing keys remain local. Static checks and 14 artifact verifier cases pass;
  the real Xcode integration run remains next.
- A fresh bounded read-only DAC snapshot is complete. The user reserved unused
  memory slots for qualification; EQ 20 and setup 9 are selected. No memory
  write is claimed here, and the accepted fader behavior is unchanged.
- Next: run native CI, qualify memory on the physical DAC, validate/sign the
  release package, finish Apple account fields and attach actual review assets.

## 2026-11-11 — Animate the main fader for physical-knob feedback

- Replaced the main fader renderer with a native AppKit control whose track,
  fill and knob use Core Animation layers. Incoming targets ease over 0.18 s
  from the current presentation position, retargeting without endpoint jumps
  or overshoot. Direct input stays immediate and quantized to 0.1 dB; keyboard,
  accessibility, focus and Reduce Motion remain supported. Animation emits no
  user-value callbacks or interpolated MIDI.
- The prior readout/tiny-level-bar smoothing was rejected by the user because
  the actual main fader still jumped while turning the physical DAC knob. That
  decorative indicator was removed. A read-only observation captured 86 live
  knob reports with a typical interval of 64.3 ms; device cadence is unchanged.
- Validation: 10 isolated component cases / 48 assertions pass, sampling actual
  presentation geometry across display frames, retargets/reversal, direct input,
  0.1 dB keyboard/accessibility steps, Reduce Motion, disabled input and callback
  separation. A mid-animation drag regression also verifies input starts from
  the actual volume rather than an intermediate animation frame. The universal
  sandboxed build and bundle checks pass. Reproducible
  CLT motion-harness instructions are in `macOS/README.md`.
- Reopened the new universal development app after the user quit the previous
  build, connected it and restored the pending EQ draft without applying it.
  The user tested the physical DAC knob and confirmed: “It’s smooth now.” No
  hardware parameter write or EQ Apply was performed by this change's checks.
- Acceptance covers the observed live DAC volume feedback. App Store signing,
  full Xcode archive validation and the other documented hardware workflows
  remain separate release gates.

## 2026-11-11 — Smooth volume feedback

- Added brief eased volume readout/level transitions, keeping direct dragging,
  native 0.1 dB stepping and Reduce Motion behavior. Animation is confined to
  presentation; the hardware binding and MIDI model are unchanged.
- Validation: universal release build and sandbox/signature checks pass; native
  demo accessibility adjustments remain exactly 0.1 dB. Independent code review
  confirms no animation path can send interpolated MIDI. No new tests needed for
  this presentation change; protocol and model source are unchanged.
- Reopened the updated app, read the live DAC volume, and restored the user's
  pending EQ draft from an export without applying it or changing hardware state.
- Source publication and remaining App Store release gates are unchanged.

## 2026-11-11 — Correct shared EQ controls and verify physical DAC communication

- A real DAC returned 219 parameters; the first Mac connection timed out because
  the port incorrectly required a right-side Bass/Treble flag. Aligned readiness,
  flag hydration, profile writes, preset selection and right-side controls with
  RME MIDITable v1.2's documented left-only shared controls.
- Validation: 50 Swift cases / 323 assertions pass. The universal sandboxed app
  connects to the DAC, reads live EQ, and writes/reads/restores a 0.1 dB Phones
  volume change. No persistent memory slot was written. Details and remaining
  acceptance are in `macOS/HARDWARE_TESTING.md`.
- Source publication still awaits the publishing account's repository write
  access decision. Full Xcode, distribution signing and wider hardware tests
  remain release requirements. No Apple submission or account change occurred.
- Next: validate EQ/preset workflows and the distribution-signed Xcode archive.

## 2026-11-10 — Profile library and device memory parity

- Added sandbox-local profile Save/Load, 20 EQ preset slots and nine device
  setups, preserving explicit draft Apply and confirming live recall/overwrite.
- Device preset storage uses the Linux app's exact five-band staging/commit/name
  frames; Bass/Treble and Loudness remain separate from device slot writes.
- Validation: 30 core cases/143 assertions and 16 fake-MIDI app cases/106
  assertions pass. Universal build and sandbox signature checks pass. Native
  profile Save/Load and simulated preset/setup save/recall confirmations were
  exercised. Physical hardware memory writes remain unverified.
- Fixed a duplicate destination label and shortened the sidebar label after
  reviewing the native screen. No Linux runtime or production deployment change.
- Release next step: qualify the signed sandbox on physical ADI-2 hardware and
  validate the full Xcode archive with genuine Apple signing credentials.

## 2026-11-10 — Native macOS application

- Added ADI-2 Companion alongside the Linux app: SwiftUI, CoreMIDI, EQ drafting,
  independent channel parameters, portable imports/exports and offline demo.
- Added strict fresh-state synchronization, device pairing and callback session
  guards, input validation and injectable MIDI transport for regression tests.
- Added an Xcode project, original icon, minimal sandbox entitlements, privacy
  material, universal development bundle scripts and macOS/Linux CI.
- Validation: 25 protocol/core cases (108 assertions), 11 fake-MIDI app cases
  (70 assertions), and 19 Linux tests pass; GTK module skipped on macOS.
  Both arm64 and x86_64 release slices compile and pass bundle/signature checks.
  Native sandbox UI editing, Apply in demo, export/import and disconnected
  controls verified. A native exported profile loads through the Linux model.
- Release: development only. Real DAC sandbox qualification, full Xcode archive,
  Apple distribution signing and hardware camera review video remain required.
- Next: run native CI and qualify the final signed app with physical hardware.

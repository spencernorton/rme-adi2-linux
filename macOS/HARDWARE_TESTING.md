# macOS hardware qualification

## 2026-11-11 — Signed build 1 and first-release scope decision

Distribution-signed ADI-2 Companion 1.0.0 (1), from the verified `ec848fc`
archive, was tested with an ADI-2 DAC on Apple silicon and macOS 27.2. The signed
app connected, read the fresh 219-parameter state, and completed a neutral EQ
Apply followed by fresh hardware readback. The prior basic volume/readback
and accepted physical-knob feedback observations remain limited to this DAC
workflow; they do not establish arbitrary EQ transitions or every parameter.

The DAC was observed at USB 80 / DSP 55 and later USB 81 / DSP 62. Bounded
memory diagnostics returned all 34 stored EQ band values matching the fresh
Phones baseline, but the requested name did not round-trip. An isolated
name-only attempt after the commit had settled failed on USB 80 / DSP 55.
The full save/name path failed again on USB 81 / DSP 62 after the update.
The cause remains unknown; neither a different commit index nor an alternate
name encoding was established. The memory diagnostics were isolated unsigned
helpers using native protocol/model paths, not evidence of a successful memory
workflow in the final signed app. No complete EQ/setup recall qualification was
accepted from those attempts.

Persistent device EQ/setup storage, naming and recall are excluded from the
first paid Mac release. The prepared scope patch disables the immutable device
memory capability, removes the associated UI and generic controls, and rejects
model entry points. Local profiles, offline EQ editing and live EQ/volume/
non-memory parameter controls remain in scope. Internal protocol code, explicit
opt-in development tests and Linux behavior are retained. There is no user
switch or release promise for device memory.

Build 1 was delivered, processed and attached to the App Store Connect version
draft, together with two screenshots and a physical-camera hardware video.
No App Review submission or public release has occurred. Planned build 2 has
not yet been built, signed, uploaded or hardware-qualified. The scope patch
passed the existing CLI software checks: 51 cases / 342 assertions, zero failures
(33 core / 205 assertions and 18 app-model / 137 assertions), using fake MIDI.
This is not physical qualification of build 2. Pro/2/4 hardware,
Intel runtime behavior, other OS versions and unplug/replug remain unqualified.

The earlier entry below preserves its original development-test scope and
remaining-work statements; the later evidence above supersedes those statuses.

## 2026-11-11 — ADI-2 DAC, basic sandbox communication

Test environment: Apple silicon Mac, macOS 27.2, ADI-2 DAC USB MIDI Port 1,
ADI-2 Companion 1.0.0 development build. The app was ad-hoc signed with only
App Sandbox and user-selected file read/write entitlements.

Verified:

- The physical DAC is discovered and its input/output endpoints are paired.
- A bounded read-only CoreMIDI probe receives 219 parameters without malformed
  SysEx frames. The sandboxed app connects and displays live EQ and output state.
- The app changes Phones volume down by 0.1 dB, synchronizes from the device,
  restores the initial value, and synchronizes again. Both hardware readbacks
  match the intended values. No preset or setup slot was written.

The first physical test exposed a sync bug: readiness incorrectly required a
right-side Bass/Treble switch that the device does not report. RME's official
MIDITable v1.2 documents EQ enable, Bass/Treble and preset selection on left EQ
addresses. The corrected app reads shared flags there, offers right-side band
controls only, and keeps complete left/right band validation before writes.
The firmware may report right-side EQ enable; this optional data does not
expand the documented write contract.

Primary reference: [RME protocol download](https://www.rme-audio.de/downloads/adi2remote_midi_protocol.zip),
`MIDITable_ADI-2_261030.ods`, `Channels!A80:G80`, `G99`, `A100:B106`,
`G107`, `A108:H110`. See the [Remote manual, page 3](https://rme-audio.de/downloads/adi2remote_e.pdf)
for the official protocol link. Synthetic regression tests preserve this
reported field shape without storing a real device's serial or personal EQ.

## Remaining acceptance

This is a basic communication result for one DAC and one Mac/OS combination.
It does not establish Pro/2/4 Pro support, Intel runtime compatibility, other
macOS releases, physical unplug/replug or power-cycle recovery, EQ Apply
readback, or persistent preset/setup memory writes. These still need tests on
the final signed build. Do not overwrite a user's saved memory slots as a test.

Full Xcode archive/XCTest validation, Apple distribution signing, App Store
Connect metadata and Apple's hardware demonstration video also remain open.
The development host currently has Command Line Tools and no signing identity.

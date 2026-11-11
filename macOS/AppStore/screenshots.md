# Screenshot shot-list

Capture genuine views of the final app. This plan is not a set of completed
screenshots and does not authorize hardware changes during capture.

Two build 1 screenshots are attached to the existing App Store Connect draft.
Build 2 is a planned, unbuilt scope change; verify or recapture its final UI
before using these instructions as evidence of the shipping build.

## Capture format

Use one consistent **2880 × 1800 pixel** output size, or **1440 × 900 pixels**
if the capture surface is not Retina. Both are accepted Mac sizes with a 16:10
aspect ratio. Apple accepts PNG/JPEG, requires at least one screenshot, allows
up to ten per device size, and forbids alpha channels/transparency. Its other
accepted Mac sizes are 1280 × 800 and 2560 × 1600. Check actual exported pixel
dimensions, not just window dimensions in points. Source:
[Apple screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/),
checked November 11, 2026.

Keep the real title bar and enough sidebar/banner context to identify the app
and its state. Use a rectangular opaque capture; window-shadow screenshots may
contain transparency. Do not stretch the interface, invent controls, overlay a
fake Connected label, or remove a demo notice from a shown feature.
Avoid unrelated windows, personal files, endpoint identifiers and private profile
names. Use original app artwork; do not add RME logos or endorsements.

## Isolated app clone for capture

Use `prepare-capture.sh` to copy an existing verified development app and re-sign
only the copy with bundle ID `tech.norvi.ADI2Companion.AppStoreCapture`. It keeps
the executable code, app artwork and visible product name unchanged. The new
bundle identity gives it a separate sandbox/library/preferences container. The
script does not build or launch anything and refuses to replace an existing
capture clone. From `macOS`:

```sh
./AppStore/prepare-capture.sh "/absolute/path/ADI-2 Companion.app" "/absolute/path/capture-output"
```

Then the UI operator may explicitly open that exact copy with `--demo`:

```sh
open -n "/absolute/path/capture-output/ADI-2 Companion Capture.app" --args --demo
```

Select the capture process by its unique bundle ID, not its shared product name.
Keep the already connected real app open and untouched. Confirm the capture
window's demo banner before editing/importing/saving synthetic profiles; never
choose Connect in this clone. Demo may enumerate available MIDI endpoints but
does not connect to or send control messages to the DAC. Do not clear or reuse
the real app's sandbox or profile files.

Capture the first three views in demo; for the optional offline view, leave demo
in the clone only. Its separate local library can contain the synthetic capture
profiles without exposing the user's real library or pending hardware-session
draft. Close only the capture process after capture. These instructions do not
replace checking each screenshot's actual state and pixel dimensions.

## Recommended first three images

Perform capture in a separate demo/offline session. Preserve the user's active
hardware session and pending draft. The fixture names below are relative to
this directory. Local profile saves in a dedicated demo session are local disk
operations; they do not demonstrate hardware memory writes.

| Order / filename | Screen and preparation | What must be visible | Purpose |
| --- | --- | --- | --- |
| 1 / `01-five-band-eq.png` | Explore demo; choose Phones 1/2; import `fixtures/listening-profile.json`. Leave the draft unapplied. | The visible demo banner, main fader, response graph, all five bands and Apply action. Use the new whole-fader build. | Show the native five-band editor and explicit draft workflow. A static screenshot does not prove smooth motion. |
| 2 / `02-import-review.png` | In demo, import `fixtures/import-example.txt`; scroll only as needed to show the result and import adjustments. | The demo banner, resulting five-band EQ and actual warnings about reduction/preamp handling. Capture after the file picker closes. | Show that imports are reviewed and hardware-limit adjustments are reported. Do not imply seven bands or a preamp are applied to the DAC. |
| 3 / `03-local-profiles.png` | In the isolated session, save two or three clearly named example profiles; choose Local profiles in the sidebar. | Destination output, Local profile library, saved example names and Load draft actions. | Show local storage and reusable EQ drafts. |

## Optional supporting images

| Filename | Screen and preparation | Visible context and claim limits |
| --- | --- | --- |
| `04-offline-editor.png` | Leave demo in the isolated session; import `fixtures/listening-profile.json` while disconnected. | Keep Disconnected visible and Apply disabled. Show that profiles can be edited without hardware; do not relabel the state as live. |
| `05-connection-help.png` | Open the app's connection-help sheet. | Show the genuine USB/MIDI setup instructions and demo option. Do not show an unrelated device or a simulated hardware success. |
| `06-device-settings-demo.png` | Explore demo with the DAC model and open Device settings. | Retain the demo banner. Describe this as exploring controls, not a verified hardware-setting write. Pro-only controls are not needed for this listing. |

A live DAC screenshot is optional and should be read-only: use the already
connected final build, display current settings without moving controls, and
avoid any pending personal EQ draft or private endpoint information. Do not
change physical volume, apply EQ, recall/save memory, or adjust routing solely
to manufacture a marketing frame.

## Final visual review

Confirm that screenshot text matches the actual app and metadata, labels are
readable at product-page scale, the curve and band values agree, no dialog hides
the key feature, and the app state is honest. Keep at least the three recommended
views if they remain distinct and legible. A short product preview video is
optional and separate from Apple's required physical-camera hardware-review
video.

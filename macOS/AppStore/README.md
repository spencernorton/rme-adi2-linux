# App Store submission draft

Prepared November 11, 2026 for the first paid Mac release: local profiles,
offline EQ editing, and live ADI-2 DAC EQ/volume/parameter controls. The existing
app record uses a USD 15.00 upfront base price and SKU
`tech.norvi.adi2companion.mac`.

Version 1.0.0 build 1 was delivered, processed and attached to the version draft,
with two screenshots and a physical-camera hardware video. No App Review
submission or public release has occurred. This directory now describes planned
build 2, whose scope change has not yet been built, signed, uploaded or
hardware-qualified. Do not apply its claims to the already uploaded build 1.

The baseline source is public after PR 1 merged as
`9ef636f07a00a07a3e9d3deff5dd972eaa0996ee`. Anonymous checks at
19:25:27 UTC on November 11 verified the GitHub HTML and raw support, privacy
and Mac README URLs: all returned HTTP 200, with expected titles and raw bytes
matching `dfade65`. This first-release scope follow-up is still unpublished;
verify the updated pages after its merge.

`metadata-en-US.json` contains reviewable English (US) strings and preparation
status. It is not an App Store Connect API request. Its `source_revision` names
the pre-scope baseline; record the actual reviewed build 2 revision when it
exists. No private account or review-contact fields belong in this public pack.

## Copy and asset checks

| Field | Draft length | Apple limit |
| --- | ---: | ---: |
| Name | 15 characters | 30 characters |
| Subtitle | 30 characters | 30 characters |
| Promotional text | 155 characters | 170 characters |
| Description | 2,075 characters | 4,000 characters |
| Keywords | 73 UTF-8 bytes | 100 bytes |
| Review notes | 2,628 UTF-8 bytes | 4,000 bytes |

The keywords use generic terms of at least three characters and omit company
names. Promotional text is optional; use it only where available for this
platform. A first release has no What's New field. Sources:
[app information](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information/)
and [platform version information](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information/),
checked November 11, 2026.

See [the screenshot guide](screenshots.md). Fixtures are original examples,
not a user's saved EQ or measurements. Import them only into an isolated
local demo/offline session; they are not listening advice.

The listing uses **ADI-2 Companion** and original artwork. Hardware names
identify compatibility; do not add RME logos or imply endorsement. It covers
local profiles, offline editing and live DAC controls, with no offer of device
preset/setup memory operations. Pro/2/4 hardware remains unqualified. These
listing boundaries must match the actual final binary.

## Required field status

| Item | Recorded preparation | Remaining action |
| --- | --- | --- |
| Product record | ADI-2 Companion; macOS; English (US); Music | Keep existing identity consistent with the signed app |
| SKU | `tech.norvi.adi2companion.mac` | Preserve the existing SKU |
| Bundle ID | `tech.norvi.ADI2Companion` | Match the genuine build 2 archive |
| Version / build | 1.0.0 / planned build 2 | Build 2 has no archive, signature or upload result yet |
| Pricing | USD 15.00 upfront, one time; no in-app purchases or subscriptions | Verify the actual final storefront prices |
| Listing | Strings fit checked Apple limits | Replace draft preparation status with verified final evidence before submission |
| Public support/privacy | Baseline HTML/raw pages verified HTTP 200 at 19:25:27 UTC | Publish and reverify the scope follow-up; reconcile policy/contact with the final app |
| Screenshots | Two build 1 images attached | Verify or recapture the final scoped UI; preserve honest demo labels |
| Hardware video | Physical-camera Mac/DAC video uploaded for build 1 | Reconcile with the submitted build and tested environment |
| Questionnaires | Existing account answers are outside this public pack | Reconcile privacy, age rating, export and applicable declarations with the final app |
| Distribution | Build 1 delivered, processed and attached | Build, validate, sign, upload and select the actual build 2 |
| Review submission | None | Complete release gates before submitting |

## Public support and privacy

Apple's [Support URL definition](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information/)
requires actual contact information as applicable under local law, and
[Guideline 1.5](https://developer.apple.com/app-store/review/guidelines/#developer-information)
requires an easy contact route. The preparation patch does not add private
contact data or guarantee acceptance of GitHub as the sole support channel.
The baseline pages are already verified live. Recheck the updated pages and
applicable requirements after the scope follow-up merges and before submission.

The source declares no app-operated collection or tracking. Keep the
corresponding privacy answers only if the final binary and dependencies still
match that behavior. Do not infer a complete Accessibility Nutrition Label
assessment from the fader's component tests.

## Evidence boundaries

Follow [APP_STORE.md](../APP_STORE.md) and the preserved
[hardware record](../HARDWARE_TESTING.md). The distribution-signed build 1
completed a neutral EQ Apply with fresh readback, and basic DAC sync/volume
checks were observed on Apple silicon with macOS 27.2. This does not qualify
arbitrary EQ transitions, every parameter, Pro/2/4 hardware, Intel runtime or
other OS combinations. The build 2 scope patch passed 51 CLI software cases /
342 assertions with zero failures using fake MIDI; it has no app archive or
new physical-hardware qualification yet.

Apple requires a physical-camera hardware-interaction video, not a screen
recording, plus the tested device/OS information. The existing video is an
uploaded asset, not an approval. [Complete review information](https://developer.apple.com/help/app-review/before-submitting-for-review/complete-review/)

Review notes intentionally record the current unbuilt status. Reconcile those
notes, the exact tested revision/firmware, final assets and private review
contact before any actual submission.

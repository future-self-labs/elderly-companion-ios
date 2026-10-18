# HelloNoah — iOS

Native iOS app of **HelloNoah.ai**: Noah, a Dutch, voice-first AI companion for older people.
The family caregiver (*mantelzorger*) buys and sets it up; the older person just talks to Noah.
A product by Aldery.

- Product spec: `HelloNoah.ai — Product & Research Handoff.md` (Section 1 is binding).
- API contract: [`../elderly-companion-api/docs/api-v2.md`](../elderly-companion-api/docs/api-v2.md) (API v2).
- Screenshots of every screen (mock mode): [`docs/screenshots/`](docs/screenshots/).

## Two interfaces in one app

At launch the app decides by what is in the Keychain:

| Keychain | Interface |
|---|---|
| device token (`hnd_…`) | **Older person** — formal "u", huge targets, no login ever |
| caregiver tokens | **Caregiver** — informal "je", tab bar |
| nothing | Welcome: "Ik ben mantelzorger" or "Deze telefoon is voor iemand die met Noah gaat praten" (6-digit pairing code) |

**Older person:** Home (big round "Praat met Noah", last conversation, "Vertel een verhaal" (story mode), "Bel mij",
next reminder, Mijn verhaal, Herinneringen) · Conversation (orb + waveform reacting to who speaks, optional large
subtitles, big "Ophangen", calm "Wordt opgenomen als u ja zegt" when the server records; at accessibility text sizes a
compact one-line header, the latest subtitle line and controls pinned above the home indicator) · Mijn verhaal (by
topic or by period, detail, "Luister naar uw verhaal" with their own voice) · Herinneringen (a memory aid next to what
they already use) · widgets (small, medium, lock-screen circular) that start a conversation at once. Any other
`hellonoah://praat|verhaal` link (web page, message, another app) opens the conversation screen with one big start
button: the microphone only opens after a visible tap. The widget proves it is the widget with a per-install token in
the shared Keychain group `<team>.ai.hellonoah.shared` (`Shared/WidgetLaunch.swift`). A hidden long-press (2 s) on the greeting opens settings for the
caregiver (unpair this phone).

**Caregiver:** 4 welcome slides · Sign in with Apple / phone + SMS code · start (new profile or invitation code) ·
9-step profile wizard (name & address form, phone, about, important people, preferences, Noah settings, emergency
contacts, pairing code, subscription) · dashboard (alerts, latest summary, week stats, 7-day mood chart, upcoming
reminders, life story, "Laat Noah nu bellen" as a normal or story call, push pre-prompt, trial/inactive banners) ·
conversations (paginated, story chip, inline "Luister") + detail with recording player and transcript · life story
(topics / timeline, add/edit/delete, "Luister naar Wim" from the story's `startSeconds`) · reminders (once / daily /
weekly, Noah calls or mentions it; always with the memory-aid disclaimer) · mood (7/30/90 days, Swift Charts) · alerts list + detail (acknowledge, resolve, "vals alarm") ·
Meer: Noah settings (incl. recording: uit / alleen bij levensverhalen / alle gesprekken), profile, important people, emergency contacts (reorder), Noah's phone number (add to contacts),
caregivers & invitations, pairing, paired devices, subscription (with fair-use usage this month), account (GDPR export, delete with "VERWIJDER"),
switching between older people. A `lezer` sees no edit controls and none of the beheerder-only screens.

## Run it

```sh
brew install xcodegen          # once
xcodegen generate              # after changing project.yml (the generated project is committed)
open HelloNoah.xcodeproj       # ⌘R
```

### Mock mode (no backend, no ElevenLabs)

The scheme passes `-useMockAPI YES`, so **⌘R runs the whole app against an in-app mock of API v2**
(`HelloNoah/Core/Mock`): caregiver Anna de Vries, her father Wim (beheerder) and aunt Riet (lezer), a month of
conversations, mood, life story, reminders and alerts, plus a scripted conversation with fake audio levels.
Uncheck the argument in *Edit Scheme → Run → Arguments* to use the live backend.

- Sign in with Apple → Anna. Phone number + any 6-digit code → a brand-new caregiver (walk through the wizard).
- Pairing: any 6 digits pair the phone with Wim. `000000` is always rejected (error states). A code from a
  `hellonoah://koppel/…` link is only filled in; pairing needs a tap on "Koppelen". Invitation links likewise only fill
  in the code.
- Hidden toggle (**Debug builds only**; the mock, the toggle and all launch arguments are compiled out of Release, so
  TestFlight and the App Store always use the real backend): tap the HelloNoah logo on the welcome screen 5×, or
  long-press the version line in *Meer → Account en privacy*.
- Handy launch arguments (mock only): `-mockPersona caregiver|new|elder|none`, `-uiRoute <screen>` (e.g.
  `dashboard`, `conversationDetail`, `storyConversationDetail`, `alertDetail`, `wizard`, `paywall`, `conversation`,
  `storyConversation`, `myStory`, `storyEntry`; see `CaregiverRootView.applyDebugRoute` / `ElderRootView`),
  `-mockOffline YES`, `-mockInactive YES`, `-mockOverAllowance YES` (fair use used up), `-mockLatency 0`,
  `-mockMaxDurationSeconds 70` (short sessions: Noah is asked to say goodbye a minute before the end),
  `-mockRecordingUnavailable YES` (recording changes answer 503), `-mockAppleIDPaysFor <elderlyId>` (this Apple ID
  already pays for that profile: the paywall explains instead of selling), `-mockPhoneUnverified YES` (Wim's number
  still needs confirming; any 6 digits except `000000` confirm it).
- Recordings (v2.1): Wim's recording setting is "alleen bij levensverhalen"; his story conversations and two life-story
  entries (trouwdag, Toon Hermans) have a recording. Mock mode plays a generated 40-second demo tune instead of a voice.
- Purchases: mock mode always simulates the purchase and never touches StoreKit (no real charge, nothing finished
  against the mock). `Products.storekit` (`ai.hellonoah.abonnement.maand`, intro €9,99 × 6, then €59,99) is used when
  running live from Xcode.

Mock data lives in memory and resets at each launch.

### Live

Base URL: `Config/HelloNoah.xcconfig` (`API_BASE_URL`, default
`https://elderly-companion-api-production.up.railway.app/api/v2`), override at runtime with
`-apiBaseURL https://…`. Terms/privacy/support links are in the same file.

### Tests

```sh
xcodebuild -scheme HelloNoah -destination 'platform=iOS Simulator,name=iPhone 15 Pro' build test
```

90+ unit tests (incl. `AuditFixesTests` and `ConversationControllerTests` for the 2026-10-18 audit fixes): every example of the contract decodes, tolerant decoding (unknown fields/enum values, missing
arrays), request encoding, single-flight token refresh (5 parallel 401s → exactly 1 refresh), sign-out on an invalid
refresh token, device unpairing on 401, Dutch relative dates and reminder schedules, phone number normalisation,
role gating (incl. the mock enforcing it), deep links, and the v2.1 product corrections (fair use, recording setting,
story mode, audio URLs and expiry, memory-aid and privacy copy, and a scan of the compiled strings for forbidden claims
like "onbeperkt" or "geen geluidsopnames").

## Product wording (v2.1)

The plan is named only in `Plan.displayName` ("HelloNoah-abonnement", `Core/Services/SubscriptionStore.swift`). Texts
that must read the same everywhere live in `ProductCopy` (`Core/Formatting/Labels.swift`): the honest privacy text,
the reminder disclaimer (short and full), the older person's reminder line and the fair-use sentence. Never claim
unlimited talking, "geen geluidsopnames" or "alle gegevens in de EU".

## Structure

```
project.yml                 xcodegen (app, widget, tests; iOS 16; team 465F27GDQR)
Config/HelloNoah.xcconfig   base URL and legal links
Shared/Tokens.swift         design tokens (colours, type, spacing, radii, sizes) — app + widget
HelloNoah/
  App/                      @main, AppModel (mode, sessions), deep links, router
  DesignSystem/             UIKit appearance + components (buttons, cards, rows, inputs, chips, states, orb)
  Core/Models               Codable models of API v2 (+ tolerant decoding helpers)
  Core/Networking           APIClient (auth, errors, single-flight refresh), NoahAPI protocol, LiveNoahAPI
  Core/Mock                 MockNoahAPI + Dutch sample data
  Core/Voice                ConversationController, ElevenLabsVoiceEngine, MockVoiceEngine
  Core/Services             StoreKit 2, push, reachability
  Core/Formatting           Dutch dates, schedules, phone numbers, labels
  Features/Welcome|Elder|Caregiver
  Resources/                fonts (+ OFL licences), assets, Localizable.xcstrings, PrivacyInfo.xcprivacy
HelloNoahWidget/            WidgetKit extension
HelloNoahTests/             unit tests + contract fixtures
```

### Design system

Direction "B · Avond": ground `#13203A`, surfaces `#1D2D4D`/`#0E182D`, amber accent `#F2B84B`, coral hang-up
`#E2725B`, DM Serif Display for titles and Lexend for copy (both OFL, bundled with their licences). **All visual
decisions live in `Shared/Tokens.swift` and `HelloNoah/DesignSystem/`**; feature views only use tokens and
components, so a redesign is mostly a token change. Custom fonts scale with Dynamic Type (`relativeTo:`); very long
display titles are capped at accessibility size 1 to avoid mid-word breaks, body text keeps scaling.

### Voice

`POST /device/conversation` → `ElevenLabs.startConversation(conversationToken:config:)` (Swift SDK 3.4) with the
returned `dynamicVariables` (typed) and `overrides` (prompt, first message, language, voice, speed) unchanged. The app
owns the audio session (`.playAndRecord`, `.voiceChat` for echo cancellation, loudspeaker, Bluetooth), drives the orb
and waveform from a renderer on the agent's `RemoteAudioTrack` (Noah) and the mic renderer + server VAD score (the
older person), with a calm synthetic wave when no levels arrive, ends calmly on an incoming phone call, shows
network hiccups, enforces
`maxDurationSeconds`, keeps the screen awake and continues with the screen locked (background audio).

## Strings

Dutch is the development language and the only compiled language (`XCSTRINGS_LANGUAGES_TO_COMPILE = nl`).
Xcode fills `Localizable.xcstrings` automatically when building in the IDE; from the command line run
`xcrun xcstringstool sync HelloNoah/Resources/Localizable.xcstrings --stringsdata <files>` with the `.stringsdata`
files from the build's intermediates.

## Release checklist (Apple)

See the report in `LOG.md` (2026-10-11): App ID capabilities (Sign in with Apple, Push, Associated Domains), the
widget App ID, the auto-renewable subscription `ai.hellonoah.abonnement.maand` ("HelloNoah-abonnement") in group "Noah" with the 6-month
pay-as-you-go intro offer, App Store Server Notifications V2 URL, APNs key for the backend, AASA file on
hellonoah.ai, TestFlight.

```sh
xcodegen generate
xcodebuild archive -project HelloNoah.xcodeproj -scheme HelloNoah -configuration Release \
  -destination "generic/platform=iOS" -archivePath build/HelloNoah.xcarchive -allowProvisioningUpdates
```

# Noah - Elderly Companion: Project Log

Last updated: 2026-10-18

---

## Systems Architecture

```
+---------------------------------------------------------------------+
|                          Noah Platform                                |
+---------------------------------------------------------------------+
|                                                                       |
|  +-------------------+       +----------------------------------+    |
|  |   iOS App          |       |  Backend API (Railway)           |    |
|  |   (Swift/SwiftUI)  |------>|  Hono + Drizzle + PostgreSQL     |    |
|  |   elderly-companion|       |  elderly-companion-api repo      |    |
|  |   -ios/            |       +----------------------------------+    |
|  +-------------------+              |         |         |            |
|          |                          |         |         |            |
|          |  LiveKit WebSocket       |         |         |            |
|          v                          v         v         v            |
|  +-------------------+   +-----------+  +-----------+ +----------+  |
|  | LiveKit Cloud      |   | Twilio    |  | Zep Cloud | | Supabase | |
|  | (Real-time voice)  |   | (SMS/OTP  |  | (Memory)  | | Storage  | |
|  +-------------------+   |  + calls   |  +-----------+ | (Audio)  | |
|          ^                |  + WhatsApp|                +----------+ |
|          |                +-----------+                               |
|  +-------------------+                                               |
|  | LiveKit Agent      |                                              |
|  | (Python worker)    |   Two voice modes:                           |
|  | elderly-livekit-   |   1. OpenAI Realtime (all-in-one)            |
|  | server-python/     |   2. Pipeline (Deepgram+GPT4o-mini+11Labs)   |
|  +-------------------+                                               |
|                                                                       |
|  +-------------------+                                               |
|  | Marketing Website  |                                              |
|  | (React/Vite)       |                                              |
|  | noah-family-voice/ |                                              |
|  +-------------------+                                               |
+---------------------------------------------------------------------+
```

### Repositories

| Repo | GitHub | Purpose | Deployment |
|------|--------|---------|------------|
| **elderly-companion-ios** | `future-self-labs/elderly-companion-ios` | iOS app (Swift/SwiftUI) + server source | App Store / (source for API) |
| **elderly-companion-api** | `future-self-labs/elderly-companion-api` | Backend API (deployed copy of server/) | Railway |
| **elderly-livekit-server-python** | `future-self-labs/elderly-livekit-server-python` | LiveKit voice agent "Noah" | Railway |
| **noah-family-voice** | `future-self-labs/noah-family-voice` | Marketing landing page (React/Vite) | Lovable.dev |

**IMPORTANT**: The backend API lives in `elderly-companion-ios/server/` AND is separately deployed from `elderly-companion-api`. Both must be kept in sync. Use `rsync` to copy `server/src/` to `elderly-companion-api/src/` before pushing.

---

## Directory Structure

```
ElderlyCompanion/
  ElderlyCompanion.entitlements       # HealthKit entitlement
  App/
    ElderlyCompanionApp.swift, AppState.swift, RootView.swift, MainTabView.swift, Info.plist
  Core/
    Models/        User.swift, Call.swift, Reminder.swift, Memory.swift, NoahLanguage.swift
    Network/       APIClient.swift (all endpoints, JWT auth, care/people/events/stories/wellbeing)
    Services/      AuthService, KeychainService, LiveKitService (Realtime + Pipeline transcription, stream dedup),
                   CalendarService, NotificationService, HealthKitService
  Features/
    Home/          HomeView (Talk Now, Talk Now Pipeline, Call Noah), HomeViewModel
    Conversation/  ConversationView (usePipeline flag, voiceId), ConversationViewModel
    Onboarding/    OnboardingContainerView, Welcome, LanguagePicker, Profile, Phone, Calendar, Notifs, Legacy
    Routines/      ScheduledCallsView (delete w/ trash icon), RoutinesView
    Calendar/      CompanionCalendarView
    CallHistory/   CallHistoryView (fetches real transcripts)
    Legacy/        LegacyArchiveView (Transcripts/Timeline/Starred tabs, export button), LegacyStoriesView
    Activity/      ActivityOverviewView
    Health/        HealthSettingsView (Apple Health, live stats, sharing toggles)
    People/        PeopleView (Memory Vault — add/view/remove people with birthdays)
    Family/        FamilySettingsView (WhatsApp toggles per member, auto-creates user record for inbound calls)
    Dashboard/     CaretakerDashboardView (mood, activity, concerns, topics)
    Care/          CareOrchestrationView, EscalationRulesView, OutreachLogView
    Safety/        SafetyView, EscalationView
    Privacy/       PrivacyView
    AISettings/    AISettingsView (language picker, voice picker, tone, proactive level), AIMemoryView
    Settings/      SettingsHubView (LazyView navigation), ThemePickerView
  Shared/
    Theme/         Theme.swift (design tokens, colors, typography)
    Components/    CalmCard, MoodSelector, LargeButton, TagBadge

server/src/
  index.ts                    # Route mounting, middleware, scheduler start
  middleware/
    auth.ts                   # JWT sign/verify, auth middleware
    roles.ts                  # Role middleware (resolveElderlyId, requireRole, requireAccess)
  lib/
    twilio.ts                 # Twilio client singleton
    livekit.ts                # Token generation (regular + pipeline), SIP outbound calls
    zep.ts                    # Zep memory client
    supabase.ts               # Supabase Storage for audio uploads
    care-engine.ts            # Risk scoring, L0-L4 escalation, outreach, silence monitor, baseline updater
  db/
    schema.ts                 # All tables (see Database Schema below)
    index.ts                  # PostgreSQL pool + Drizzle
  routes/
    otp.ts, livekit.ts, users.ts, memory.ts, transcripts.ts, scheduled-calls.ts,
    health.ts, family.ts (auto-creates user on add), people.ts, events.ts, legacy-stories.ts, wellbeing.ts, care.ts

elderly-livekit-server-python/
  main.py                     # Entrypoint: routes Realtime vs Pipeline via dispatch metadata
  agents/
    companion_agent.py        # CompanionAgent with all tools (movie, search, reminders, care signals)
    onboarding_agent.py       # OnboardingAgent for family members
  prompts/
    __init__.py               # Loader: load_system_prompt(), load_all_skills()
    system.txt                # Tiny system prompt (~600 chars, processed every turn)
    skills/                   # Individual skill files (loaded once into ChatContext):
      adaptive_behavior.txt, care_detection.txt, cognitive_games.txt, family_connection.txt,
      interactive_storytelling.txt, legacy_storytelling.txt, memory_vault.txt, mood_checkins.txt,
      movie_recommendations.txt, news_media.txt, proactive_companion.txt, reminders.txt,
      scam_protection.txt
  lib/n8n.py                  # N8N workflow integration
  workflows/                  # N8N workflow templates
```

---

## Tech Stack

### iOS App
- Swift 5.10, iOS 17+, SwiftUI with @Observable
- XcodeGen (project.yml), LiveKit client-sdk-swift 2.0+
- HealthKit integration, two themes (Calm + Apple)

### Backend API
- Hono (HTTP), Drizzle ORM + PostgreSQL (Railway), Twilio (SMS/WhatsApp/calls)
- LiveKit Server SDK (tokens, SIP), Zep Cloud (memory), Supabase Storage (audio)
- JWT auth, role-based access control

### LiveKit Agent
- Python 3.13, uv, livekit-agents ~1.1.4
- **Two voice modes** (routed via dispatch metadata):
  - **Realtime**: OpenAI Realtime API (all-in-one, lowest latency)
  - **Pipeline**: Deepgram Nova-2 STT + GPT-4o-mini + ElevenLabs TTS (more control, configurable voice)
- Silero VAD, noise cancellation (BVC)
- Skill-based prompt architecture (13 skills loaded from `prompts/skills/`)
- Zep Cloud for conversational memory, API calls for structured memory vault
- Care signal detection and reporting

---

## Database Schema (Drizzle — 13 tables)

### users
| Column | Type | Notes |
|--------|------|-------|
| id | UUID | PK |
| name | TEXT | NOT NULL |
| nickname, birth_year, city | various | optional |
| phone_number | TEXT | NOT NULL, UNIQUE |
| type | TEXT | default "elderly" (backward compat) |
| role | TEXT | "elderly" / "family" / "caretaker" |
| linked_elderly_id | UUID | FK -> users.id (for family/caretaker) |
| access_level | TEXT | "full" / "stories_only" / "health_only" / "dashboard_only" |
| language | TEXT | default "nl" (ISO code: nl, en, de, fr, es, tr) |
| notifications_enabled | BOOLEAN | default true |
| proactive_calls_enabled | BOOLEAN | default true |

### transcripts
| Column | Type | Notes |
|--------|------|-------|
| id, user_id, duration, messages, tags, summary, audio_url, created_at | various | conversation records with optional audio |

### scheduled_calls, health_snapshots, family_contacts
(See schema.ts for full details)

### people (Memory Vault)
| Column | Type | Notes |
|--------|------|-------|
| id, elderly_user_id, added_by_user_id, name, nickname, relationship, phone_number, email, birth_date, notes, photo_url, created_at | various | Personal network with birthdays |

### events
| Column | Type | Notes |
|--------|------|-------|
| id, elderly_user_id, person_id, type, title, date, recurring, remind_days_before, created_at | various | Birthdays, appointments, anniversaries |

### legacy_stories
| Column | Type | Notes |
|--------|------|-------|
| id, elderly_user_id, transcript_id, title, summary, audio_url, audio_duration, tags, people_mentioned, is_starred, created_at | various | Life stories captured from conversations |

### wellbeing_logs
| Column | Type | Notes |
|--------|------|-------|
| id, elderly_user_id, date, mood_score, conversation_count, conversation_minutes, topics, concerns, health_snapshot_id, created_at | various | Daily wellbeing tracking |

### care_settings
| Column | Type | Notes |
|--------|------|-------|
| id, elderly_user_id (UNIQUE), care_enabled, sensitivity, silence_window_hours, cognitive_drift_threshold, scam_threshold, ai_first_contact, max_outreach_per_week, escalation_cooldown_hours | various | Per-user care configuration |

### trusted_circle
| Column | Type | Notes |
|--------|------|-------|
| id, elderly_user_id, name, phone_number, role, priority_order, may_receive_{scam,emotional,silence,cognitive,routine}_alerts, outreach_methods, is_active | various | Enhanced contacts with per-category permissions |

### care_events
| Column | Type | Notes |
|--------|------|-------|
| id, elderly_user_id, trigger_category, risk_score, escalation_layer, description, ai_action, ai_contacted_elderly, elderly_responded, elderly_response, external_contact_id, external_contact_method, outcome, resolved_at, created_at | various | Full audit log of every detection and outreach |

### behavioral_baseline
| Column | Type | Notes |
|--------|------|-------|
| id, elderly_user_id (UNIQUE), avg_daily_conversations, avg_mood_score, avg_conversation_minutes, last_interaction, typical_active_hours, known_concerns, updated_at | various | Rolling 30-day behavioral profile |

---

## API Routes

### Public
| Method | Path | Description |
|--------|------|-------------|
| GET | /health | Health check |
| POST | /otp/create | Send OTP |
| POST | /otp/validate | Verify OTP, return JWT |
| POST/GET | /users/* | User CRUD (public for agent access) |
| GET/POST | /memory/* | Zep memory |

### Protected (JWT)
| Method | Path | Description |
|--------|------|-------------|
| POST | /livekit/get-token | Realtime voice token |
| POST | /livekit/get-token-pipeline | Pipeline voice token (with voiceId) |
| POST | /livekit/call | Outbound phone call via SIP |
| POST/GET | /transcripts/* | Transcript CRUD + audio upload |
| POST/GET/PUT/DELETE | /scheduled-calls/* | Scheduled call CRUD |
| POST/GET | /health-data/* | Health snapshots |
| POST/GET/DELETE | /family/* | Family contacts + WhatsApp updates |

### Memory Vault
| Method | Path | Description |
|--------|------|-------------|
| POST/GET/PUT/DELETE | /people/* | People network CRUD |
| POST/GET/DELETE | /events/* | Events CRUD + upcoming events |
| POST/GET/PUT/DELETE | /legacy-stories/* | Legacy stories CRUD |
| POST/GET | /wellbeing/* | Wellbeing logs + 7-day summary |

### Care Infrastructure
| Method | Path | Description |
|--------|------|-------------|
| GET/PUT | /care/settings/:id | Care settings |
| GET/POST/DELETE | /care/trusted-circle/* | Trusted circle CRUD |
| POST | /care/signal | Receive care signal from agent |
| GET | /care/events/:id | Outreach event log |
| POST | /care/events/:id/resolve | Resolve/false-alarm an event |
| GET | /care/baseline/:id | Behavioral baseline |

---

## Care Infrastructure Layer

### Escalation Architecture (L0-L4)
- **L0**: Observe + log only (no action)
- **L1**: Gentle clarification — AI calls the elderly to check in
- **L2**: Confirmed outreach — AI asks elderly for permission to contact trusted circle
- **L3**: Soft protective — try elderly first, contact trusted circle if no response
- **L4**: Critical safeguard — contact trusted circle directly (scam, severe risk, silence)

### 7 Trigger Categories
1. **Cognitive drift** — repetition, date confusion, looping
2. **Emotional** — sadness, withdrawal, hopelessness
3. **Scam** — urgent money, "don't tell family", password requests
4. **Silence** — no interaction for configured window (scheduler-driven)
5. **Medication** — missed reminders pattern
6. **Help request** — explicit "I need help", "call someone"
7. **Environmental** — "Where am I?", disorientation

### Anti-Overreach Safeguards
- Cooldown timer between escalation events
- Weekly outreach cap
- Multi-signal requirement for L3+ (need 2+ signals in 48h unless severity >= 8)
- False alarm feedback reduces sensitivity
- AI-first-contact guard (always try elderly before anyone else)

### Scheduler
- **Every minute**: Check scheduled calls
- **Every hour**: Silence monitor (checks last_interaction vs silence_window)
- **20:00 daily**: WhatsApp family updates (transcripts, health, wellbeing, stories)
- **23:00 daily**: Behavioral baseline updater (30-day rolling averages)

---

## Voice Architecture

### Three Modes
| Mode | Button | Tech | Interruptions | Echo Handling |
|------|--------|------|---------------|---------------|
| **Realtime** | "Talk Now" | OpenAI Realtime API (all-in-one) | Yes | OpenAI built-in + iOS .voiceChat AEC |
| **Pipeline** | "Talk Now (Pipeline)" | Deepgram STT → GPT-4o-mini → ElevenLabs TTS | Yes (min 0.8s) | iOS .voiceChat AEC + server BVC |
| **Phone** | "Call Noah" | OpenAI Realtime via Twilio SIP | Yes | Telephony hardware AEC (best) |

### Agent Dispatch (IMPORTANT)
- In-app modes: Single `createDispatch()` API call per room. Do NOT combine with `roomConfig.agents` in the JWT — that causes double agent dispatch (two agents in one room).
- Phone mode: Single `createDispatch()` then `createSipParticipant()`. Room name `call-{userId}`.
- Agent name: `"noah"` — all modes use the same agent, routed via dispatch metadata.

### iOS Audio Configuration
- `AudioManager.shared.sessionConfiguration` set to `.voiceChat` mode with `.defaultToSpeaker`
- This activates Apple's aggressive AEC (same as FaceTime/Phone app)
- Default `.videoChat` mode has weaker echo cancellation — do NOT use it

### Turn Detection
- **Realtime**: OpenAI server_vad (threshold=0.6, prefix_padding=300ms, silence=500ms)
- **Pipeline**: Silero VAD (min_silence=0.5s) + min_interruption_duration=0.8s + min_endpointing_delay=0.5s
- **Phone**: Same as Realtime

### Voice Selection
- 6 ElevenLabs voices selectable in Settings > Personality
- Stored in UserDefaults, passed through token request → dispatch metadata → agent → TTS
- Only affects Pipeline mode

### Prompt Architecture
- **System prompt** (`system.txt`, ~600 chars): Identity + personality + language, processed every turn
- **Skills** (13 files in `prompts/skills/`): Loaded once into ChatContext at session start
- **Memory context**: Zep facts + people network + upcoming events injected via XML tags (language-neutral)
- **Greeting**: `generate_reply()` instruction explicitly in user's language

---

## Environment Variables

### Backend API (Railway: elderly-companion-api)
```
DATABASE_URL, JWT_SECRET, PORT=3000
TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN, TWILIO_PHONE_NUMBER, TWILIO_VERIFY_SERVICE_SID, TWILIO_WHATSAPP_NUMBER
LIVEKIT_API_KEY, LIVEKIT_API_SECRET, LIVEKIT_URL
ZEP_API_KEY, AGENT_NAME="noah", SIP_TRUNK_ID
SUPABASE_URL, SUPABASE_SERVICE_KEY
```

### LiveKit Agent (Railway: elderly-livekit-server-python)
```
API_URL=https://elderly-companion-api-production.up.railway.app/api/v1
ELDERLY_COMPANION_API=https://elderly-companion-api-production.up.railway.app/api/v1
LIVEKIT_API_KEY, LIVEKIT_API_SECRET, LIVEKIT_URL=wss://test-7hm3rr9r.livekit.cloud
OPENAI_API_KEY, DEEPGRAM_API_KEY, ELEVEN_API_KEY
ZEP_API_KEY, PERPLEXITY_API_KEY, TMDB_API_KEY
```
Note: N8N is no longer used. `DEEPGRAM_API_KEY` and `ELEVEN_API_KEY` are required for Pipeline mode.

---

## Key Hardcoded Values
- API URL: `https://elderly-companion-api-production.up.railway.app/api/v1`
- LiveKit Cloud: `wss://test-7hm3rr9r.livekit.cloud`
- Bundle ID: `net.nextempire.noah` (team Next Empire BV, 465F27GDQR)
- SIP Trunk: `ST_FsnpUMR6sYFp`
- Agent name: `noah`
- JWT expiry: 30 days
- Scheduler: 60s interval
- Default ElevenLabs voice: `bIHbv24MWmeRgasZH58o` (Will)

---

## Production Readiness Status

| Phase | Status |
|-------|--------|
| Database (PostgreSQL + Drizzle) | DONE |
| Authentication (JWT + Twilio OTP) | DONE |
| Persistent Scheduler | DONE |
| Cleanup & Hardening | MOSTLY DONE |
| Apple Health Integration | DONE |
| WhatsApp Family Updates | DONE |
| Memory Vault (people, events, stories, wellbeing) | DONE |
| Pipeline Voice Mode (Deepgram + GPT-4o-mini + ElevenLabs) | DONE |
| Voice Selection (6 ElevenLabs voices) | DONE |
| Skill-based Prompt Architecture | DONE |
| Care Infrastructure Layer (L0-L4 escalation) | DONE |
| Supabase Audio Storage | DONE (wiring) |
| Latency Optimizations | DONE |
| Outbound Callback Fix | DONE |
| Transcript Deduplication (stream ID-based) | DONE |
| Transcript Export (ShareLink on cards) | DONE |
| Delete Scheduled Calls (trash icon + confirm) | DONE |
| Settings Navigation Lag Fix (LazyView) | DONE |
| Family Member Inbound Calls (auto-create user) | DONE |
| Language Preference (6 languages, onboarding + settings + agent) | DONE |
| Realtime + Phone Callback Audio Fix | DONE |
| VAD & Turn Detection Tuning | DONE |
| Outbound Call User Identification | DONE |
| iOS Echo Cancellation (.voiceChat mode) | DONE |
| Double Agent Dispatch Fix | DONE |
| Greeting Language Fix (per-user language) | DONE |
| Error Handling Hardening (Zep, SIP, sessions) | DONE |

---

## Known Issues (2026-02-16)

### RESOLVED: All Voice Modes Were Silent
- **Root cause**: `_create_zep_session` crashed with Zep 404 (API key changed) and had no try/except.
- **Fix**: Wrapped in try/except (non-fatal). Updated Zep API key on Railway.

### RESOLVED: Double Agent Dispatch (two AIs in same room)
- **Root cause**: `generateTokenAndDispatch` and `generatePipelineTokenAndDispatch` dispatched agents TWICE — once via `roomConfig.agents` in the JWT token, once via explicit `createDispatch()`. Both succeeded, two agents joined, talked over each other.
- **Fix**: Removed `roomConfig.agents`, use single explicit `createDispatch()` only. "Call Noah" was never affected (only uses one dispatch).
- **IMPORTANT**: Never combine `roomConfig.agents` with `createDispatch()` — it causes double agents.

### RESOLVED: Self-Interruption (echo)
- **Root cause**: iOS audio session defaulted to `.videoChat` mode with weak echo cancellation.
- **Fix**: Set `AudioManager.shared.sessionConfiguration` to `.voiceChat` mode with `.defaultToSpeaker`. Plus server-side: Realtime VAD threshold=0.6, Pipeline min_interruption_duration=0.8s.

### OPEN: "Call Noah" sometimes starts in English
- **Symptom**: Phone calls occasionally greet in English and say "the user" instead of the real name.
- **Likely cause**: User data lookup returning incomplete data (missing name/language fields). Added logging to diagnose.
- **Status**: Investigating via Railway logs.

---

## 2026-10-18 — Audit fixes (iOS review + security audit, API v2.2), iOS

Fixes the confirmed findings of `audit/2026-10-18-ios.md` and the iOS items of `audit/2026-10-18-security.md`, and
follows the backend's "audit fixes (v2.2)" changelog entry.

- **Voice session (H1, M2, M3, M4).** Hanging up while Noah is still being called always ends the session: the engine
  remembers the stop and ends a conversation that connects later; the controller never returns to "active" and stops a
  late engine again (microphone, agent session, idle timer released). A failed start gives the audio session back.
  `onDisconnect` is passed as the SDK argument. A minute before the maximum duration Noah gets a contextual update
  to say goodbye; at the limit the app waits up to 30 s while Noah is still talking. Status line uses the configured name.
- **Settings (H2, M11).** PATCH sends only changed fields (`NoahSettingsPatch`), so `recording` is only sent when it
  changed; a 503 on a recording change saves the rest and says so. Speaking speed rounded to 2 decimals.
- **Demo mode (H3, sec. M9).** Mock backend, mock voice, sample data, the hidden toggles and the `-useMockAPI`,
  `-apiBaseURL`, `-uiRoute` arguments exist only in Debug builds (Release binary checked: no mock symbols or demo
  strings). In mock mode StoreKit is never used.
- **One Apple ID, several profiles (H4).** Until product decides, the paywall checks this Apple ID's entitlement and
  explains that it already pays for another profile (nothing charged; another caregiver can pay with their own Apple
  ID) instead of the false "Betaling ontvangen". That text is now only shown for offline/5xx; 4xx rejections finish
  the transaction. Transactions without `appAccountToken` are finished once a profile shows an active App Store
  subscription (M6).
- **Links (sec. H4, M10, M11).** Pairing and invitation links only fill in the code and need a tap; the share text
  no longer contains the pairing link; invitation codes are validated. `hellonoah://praat|verhaal` from outside opens
  a start button; only the app's own widget (per-install token in the shared Keychain group) starts directly.
  Links not meant for the current interface are dropped; signing out on a paired phone shows the older person's home.
- **Keychain (sec. M8).** `AfterFirstUnlockThisDeviceOnly`, existing items migrated at launch. Conscious choice: tokens
  survive a reinstall on the same phone (an older person's phone stays paired; a beheerder can revoke it), never a
  backup or a new phone.
- **Accessibility (H6, M8).** Conversation screen fits at AX5 (compact header, latest subtitle line, pinned
  controls); secondary home lines no longer outgrow the greeting; next-reminder card is a button. Component borders
  #6B7FA6 (≥ 3:1), `dangerText` #F29580 for danger text (≥ 4.5:1, also on `dangerSoft`); `cardBorder` for decorative
  outlines.
- **Push (M5).** Time Sensitive Notifications entitlement (urgent/nood). App ID capability is enabled by automatic
  signing. Universal links also for `www.hellonoah.ai`.
- **Playback (M7).** RecordingPlayer follows the real player state, handles interruptions, refetches on stalls after
  expiry and on 403/410; a conversation pauses any recording.
- **Copy (M1, M10, L1, L9).** Caregiver errors use the app's own "je" text per code (server text only for unknown
  codes and only when it isn't in "u"); no "Alles inbegrepen", honest EU/AI-services wording on the paywall, no
  "Noah blijft aan de lijn", no "helpt Noah leren"; reminders default to "Overig" with a neutral example; u/je slips
  and hard-coded "Noah" fixed.
- **Privacy manifest (M9).** Also declares Health (mood, cognitive clarity, concerning signals) and Contacts
  (emergency contacts, important people). App Store Connect labels must match.
- **v2.2.** Phone numbers only +31/+32 without premium/special ranges, one Dutch message. "Bevestig het nummer" on the
  profile (code by SMS or read out; `400 ongeldige_code` never signs out). Texts for the new codes
  (`telefoonnummer_niet_bevestigd`, `_niet_ondersteund`, `belgrens_bereikt`, `te_veel_profielen`, `demo_account`,
  `te_groot`). `overrides.conversation.maxDurationSeconds` decoded (SDK can't pass it yet; client timer stays).
- **Low.** Reminder editor: past one-off reminders can be renamed/switched off, unknown schedule kinds are left
  alone. Alerts paging retries. GDPR export files protected and deleted after sharing (sec. L10). Release logging
  gated behind DEBUG (sec. L11).
- **Not changed (product/backend decisions).** iPad stays enabled (older people use tablets; App Store needs iPad
  screenshots). Device name still "iPhone" (needs the user-assigned-device-name entitlement). No UI yet to delete one
  recording. `aps-environment` stays `development` in the file (signing rewrites it on export; check the archive).
  Pairing/invitation previews (profile name before confirming) need a backend preview endpoint.
- Screenshots in `docs/screenshots/` refreshed (mock mode), new: 06, 18, 19, 51–55, 63–65.

## 2026-10-17 — Product corrections from the founder (API v2.1), iOS

Implements the 2026-10-17 changelog entry of `elderly-companion-api/docs/api-v2.md` (and the backend's v2.1 notes).

- **Fair use, no "unlimited".** Plan name only in `Plan.displayName` ("HelloNoah-abonnement"); new product id
  `ai.hellonoah.abonnement.maand` (`Products.storekit`: intro €9,99 × 6, then €59,99). Paywall explains fair use
  (10 uur per maand, daarna kortere gesprekken, Noah blijft bereikbaar); the subscription screen shows
  `usage` (minutes this month / allowance, reset date, over-allowance notice). New alert type `verbruik`.
- **Honest privacy copy** (`ProductCopy.privacy`) on the welcome slide and in Account en privacy (paywall: "Versleuteld opgeslagen in de EU");
  microphone string: recording only when the family turned it on and the older person agrees.
- **Recording setting** (beheerder only) in Noah-instellingen: Uit / Alleen bij levensverhalen / Alle gesprekken, with
  the consent explanation. Unknown future values are never sent back.
- **Story mode.** Elder home "Vertel een verhaal" (one tap, below the orb) → `POST /device/conversation`
  `{ "mode": "levensverhaal" }`; `hellonoah://verhaal` does the same. The conversation screen shows "U vertelt een
  verhaal" and, only when `recording: true`, a calm red-dot "Wordt opgenomen als u ja zegt" (Noah asks consent itself;
  the app cannot see the answer, so the wording stays conditional as the backend suggests).
- **Caregiver.** "Laat Noah nu bellen": Gewoon gesprek / Verhaal-gesprek. Conversations show the mode and a "Luister"
  button when `hasAudio`; detail has a player. Life-story entries with `audio` get "Luister naar Wim" from
  `startSeconds`. `RecordingPlayer` (AVPlayer) fetches the signed URL on tap, refreshes it when it expired (resume
  after a long pause, or `403 link_verlopen` → one automatic retry with a fresh URL), one recording at a time.
  "Mijn verhaal" detail plays the older person's own voice via `GET /device/conversations/:id/audio`.
- **Reminders = memory aid.** `medicatie` → "Medicijnen (geheugensteun)"; the contract disclaimer on the caregiver
  reminders list and editor, a short version the first time a reminder is created; elder screen: "Noah helpt u
  herinneren, naast wat u al gebruikt…". Mock transcripts no longer have Noah checking pills.
- Mock: recording setting, modes, `hasAudio`, generated demo audio, usage (`-mockOverAllowance YES`), audio 404s.
- Not done (backend additive, not asked): `DELETE /conversations/:id/audio` (remove one recording) has no UI yet.

---

## 2026-10-11 — HelloNoah v2 iOS app (replaces ElderlyCompanion)

The LiveKit-based `ElderlyCompanion` target was removed (`git rm`, recoverable from history) and replaced by the
**HelloNoah** app: API v2 (`elderly-companion-api/docs/api-v2.md`), ElevenLabs Agents Swift SDK 3.4, iOS 16+,
bundle id `ai.hellonoah.app` (+ widget `ai.hellonoah.app.widget`), Dutch only, design "B · Avond". Everything above
this entry describes the old v1 stack. See `README.md` for structure, mock mode and tests.

**Apple Developer / App Store Connect set-up still needed (founder):**
- App IDs `ai.hellonoah.app` and `ai.hellonoah.app.widget` (team 465F27GDQR). Capabilities on the app: Sign in with
  Apple, Push Notifications, Associated Domains (`applinks:hellonoah.ai`; host
  `/.well-known/apple-app-site-association` for `/uitnodiging/*`). Automatic signing creates them on first build.
- App Store Connect app "HelloNoah" (primary language Dutch), auto-renewable subscription
  `ai.hellonoah.unlimited.monthly` in group "Noah", €59,99/maand, introductory offer pay-as-you-go €9,99 × 6 months.
  App Store Server Notifications V2 → `https://…/api/v2/subscriptions/app-store/notifications`. Paid-apps agreement,
  tax and banking.
- APNs auth key (.p8) for the backend (key id + team id); sandbox for debug builds, production for TestFlight/App Store.
- Sign in with Apple: the backend verifies `aud = ai.hellonoah.app`.
- Privacy policy and terms URLs in `Config/HelloNoah.xcconfig` (privacy currently `https://hellonoah.ai/privacy`,
  terms = Apple standard EULA), App Privacy questionnaire matching `PrivacyInfo.xcprivacy`, review notes with the
  review phone number/OTP (`REVIEW_PHONE_NUMBER`).
- iPad is enabled (older people often use tablets) → App Store needs iPad screenshots too.
- One subscription group allows one active subscription per Apple ID: a caregiver who pays for two older people
  with the same Apple ID needs a product decision (second product/group, or family payment by another caregiver).

---

## 2026-10-10 — Rebrand to Next Empire, preparing test phase

- Company rebranded from **Future Self Labs** to **Next Empire**. Docs, project context and user-facing text updated on branch `next-empire/test-phase` (all four repos).
- The project is being prepared for a **test phase**. The history in this log is kept as-is (not rewritten); entries below this one describe the state as of February 2026.
- Infrastructure identifiers still carry the old name and are intentionally unchanged until decided: GitHub org `future-self-labs`, bundle ID `com.futureselflabs.elderlycompanion` (and `bundleIdPrefix` in `project.yml`, Keychain service name). Changing the bundle ID means a new App Store app record (acceptable for a fresh test phase, but a deliberate decision).
- Marketing site (`noah-family-voice`): `.env` (public Supabase keys) removed from git tracking and added to `.gitignore`.

---

## Recent Changes (2026-02-16 session)

### Transcript Deduplication
- Pipeline transcriptions were showing 2-4x duplicate messages (interim STT results treated as final)
- Fix: Track `TextStreamInfo.id` in a `Set<String>`, skip streams with already-seen IDs
- Clear set on disconnect

### Transcript Export
- Each transcript card in Memories now has an **Export** button (share icon)
- Opens iOS share sheet with formatted text: date, duration, summary, full conversation
- Can save to Files, share via Messages/WhatsApp/Email, AirDrop, etc.

### Delete Scheduled Calls
- Red trash icon on each scheduled call row
- Confirmation dialog before deletion
- Calls `DELETE /scheduled-calls/:id` API endpoint

### Settings Navigation Lag Fix
- `NavigationLink` was eagerly creating ALL destination views on settings screen load
- Added `LazyView` wrapper to defer creation until user actually taps the row
- Settings screen now feels instant

### Family Member Inbound Calls
- When a family member is added via the app, a `users` record is now auto-created with `type: "family_member"` and `linkedElderlyId`
- When that person calls the Twilio number, the agent finds them via phone number lookup and routes to `OnboardingAgent`
- No app needed on the family member's end — just the phone number

### Language Preference
- New `NoahLanguage` model with 6 options: Nederlands, English, Deutsch, Français, Español, Türkçe
- Language picker in onboarding (right after welcome, before profile)
- Language picker in Settings > Personality (above voice selector)
- Stored in UserDefaults + `language` column on `users` table (defaults to `"nl"`)
- Agent reads user's language → sets system prompt `{language}` placeholder, STT language (Deepgram/Whisper), TTS language (ElevenLabs)

### Railway Instance Cleanup
- Had two `elderly-livekit-server-python` instances on Railway (caused random routing between potentially different versions)
- Deleted both instances, recreated fresh from Git with correct env vars

### Zep Crash Fix (all modes silent)
- `_create_zep_session` had no try/except — Zep 404 error killed entire entrypoint via `asyncio.gather`
- Wrapped in try/except so agent works even if Zep is down (just without cross-session memory)
- Updated Zep API key (old one was expired)

### VAD & Turn Detection Tuning
- Realtime mode: server_vad threshold=0.6, prefix_padding=300ms, silence_duration=500ms, min_interruption_duration=0.6s
- Pipeline mode: Silero VAD (min_silence=0.5s), min_interruption_duration=0.8s, min_endpointing_delay=0.5s
- Tried EOUPlugin turn detector — doesn't exist in livekit-agents ~1.1.4 (it's `EOUPlugin`, not `MultilingualModel`)
- EOUPlugin got confused by echo-transcribed STT output; reverted to VAD-only for Pipeline

### Outbound Call User Identification Fix
- "Call Noah" and scheduled calls create room `call-{userId}` — agent now extracts userId from room name directly
- Previously relied on phone number search which was 404ing (phone format mismatch)
- Noah now correctly loads the user's name, language, memory, and context on outbound calls

### iOS Echo Cancellation Fix
- Set `AudioManager.shared.sessionConfiguration` to `.voiceChat` mode with `.defaultToSpeaker`
- LiveKit SDK defaults to `.videoChat` mode for speaker, which has weaker AEC
- `.voiceChat` activates Apple's aggressive echo cancellation (same as FaceTime/Phone app)

### Double Agent Dispatch Fix
- `generateTokenAndDispatch` and `generatePipelineTokenAndDispatch` were dispatching agents TWICE (roomConfig + createDispatch)
- When both succeeded, two agents joined the same room and talked over each other
- Removed `roomConfig.agents` entirely — now uses single explicit `createDispatch()` only
- "Call Noah" was never affected (always used single dispatch)

### Demo Hotfix: In-App Self-Interruption (Talk Now + Pipeline)
- Added app-side mic gating in `LiveKitService`: while remote participant is speaking, local mic auto-mutes; when remote stops, mic auto-unmutes
- This prevents speaker-loop acoustic feedback from being interpreted as user speech
- Manual mute intent is preserved (`userRequestedMicEnabled`)
- Result: stable half-duplex behavior in app sessions for demo reliability

### Family Member Caller Update Flow
- For inbound family-member calls (`type == "family_member"`), agent now builds a concise `family_update_brief` from:
  - `/wellbeing/:elderlyUserId/summary`
  - `/health-data/:elderlyUserId` (latest snapshot)
  - `/transcripts/:elderlyUserId` (latest summary if present)
- `OnboardingAgent` now starts by sharing a brief status update when this context exists, then asks if caller wants more details or to share updates

### Language Robustness Improvements
- Added language code normalization (`nl/en/de/fr/es/tr`, fallback `nl`) before STT/TTS/system prompt usage
- Added safer name fallback in agent prompts (prevents awkward "the user"/empty name phrasing)

### Greeting Language Fix
- `generate_reply()` instruction changed from English to user's language: `"Greet the user warmly in {language}"`
- Removed English scaffolding text from ChatContext (skills, people, events) — now bare XML tags only
- Events no longer announced upfront (removed "mention these naturally" English instruction)

### Error Handling Hardening
- `_create_zep_session` wrapped in try/except (was crashing entire entrypoint)
- SIP phone number lookup wrapped in try/except (was crashing on unknown callers)
- Pipeline session creation wrapped in try/except with API key validation logging
- Realtime session, `session.start()`, and `generate_reply()` all wrapped with traceback logging

### Railway Deployment Notes
- Nuked and recreated `elderly-livekit-server-python` service from Git
- Disabled "Wait for CI" on `elderly-companion-api` (was blocking deploys with no GitHub Actions configured)
- Updated Zep API key (old one expired)
- N8N no longer used (env vars removed)
- 2026-10-11: Aligned with StoriesFrom.ai conventions. Legal entity Next Empire, Nieuwpoortkade 2A, 1055 RX Amsterdam, KvK 63190982, btw NL855130374B01 (website legal pages updated). Bundle ID now `net.nextempire.noah`, team Next Empire BV (465F27GDQR); Keychain service renamed to match, so existing installs log in again. Needs a new App ID / App Store Connect app. GitHub org `future-self-labs` kept (StoriesFrom uses it too).
- 2026-10-11: Deployed hardened API and voice agent to Railway; shared `SERVICE_API_TOKEN` set on both services.

# Noah - Elderly Companion: Project Log

Last updated: 2026-02-16

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
    Models/        User.swift, Call.swift, Reminder.swift, Memory.swift
    Network/       APIClient.swift (all endpoints, JWT auth, care/people/events/stories/wellbeing)
    Services/      AuthService, KeychainService, LiveKitService (Realtime + Pipeline transcription),
                   CalendarService, NotificationService, HealthKitService
  Features/
    Home/          HomeView (Talk Now, Talk Now Pipeline, Call Noah), HomeViewModel
    Conversation/  ConversationView (usePipeline flag, voiceId), ConversationViewModel
    Onboarding/    OnboardingContainerView, Welcome, Profile, Phone, Calendar, Notifs, Legacy
    Routines/      ScheduledCallsView, RoutinesView
    Calendar/      CompanionCalendarView
    CallHistory/   CallHistoryView (fetches real transcripts)
    Legacy/        LegacyArchiveView (Transcripts/Timeline/Starred tabs), LegacyStoriesView
    Activity/      ActivityOverviewView
    Health/        HealthSettingsView (Apple Health, live stats, sharing toggles)
    People/        PeopleView (Memory Vault — add/view/remove people with birthdays)
    Family/        FamilySettingsView (WhatsApp toggles per member)
    Dashboard/     CaretakerDashboardView (mood, activity, concerns, topics)
    Care/          CareOrchestrationView, EscalationRulesView, OutreachLogView
    Safety/        SafetyView, EscalationView
    Privacy/       PrivacyView
    AISettings/    AISettingsView (voice picker, tone, proactive level), AIMemoryView
    Settings/      SettingsHubView, ThemePickerView
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
    health.ts, family.ts, people.ts, events.ts, legacy-stories.ts, wellbeing.ts, care.ts

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

### Two Modes (routed via dispatch metadata)
1. **Realtime** ("Talk Now"): `openai.realtime.RealtimeModel(voice="ash")` — lowest latency
2. **Pipeline** ("Talk Now Pipeline"): `deepgram.STT` + `openai.LLM(gpt-4o-mini)` + `elevenlabs.TTS` — configurable voice, better transcripts

### Voice Selection
- 6 ElevenLabs voices selectable in Settings > Personality
- Stored in UserDefaults, passed through token request → dispatch metadata → agent → TTS
- Only affects Pipeline mode

### Prompt Architecture
- **System prompt** (`system.txt`, ~600 chars): Identity + personality, processed every turn
- **Skills** (13 files in `prompts/skills/`): Loaded once into ChatContext at session start
- **Memory context**: Zep facts + people network + upcoming events injected at session start

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
API_URL, ELDERLY_COMPANION_API
LIVEKIT_API_KEY, LIVEKIT_API_SECRET, LIVEKIT_URL
OPENAI_API_KEY, DEEPGRAM_API_KEY, ELEVEN_API_KEY
ZEP_API_KEY, N8N_API_KEY, N8N_URL, PERPLEXITY_API_KEY, TMDB_API_KEY
```

---

## Key Hardcoded Values
- API URL: `https://elderly-companion-api-production.up.railway.app/api/v1`
- LiveKit Cloud: `wss://test-7hm3rr9r.livekit.cloud`
- Bundle ID: `com.futureselflabs.elderlycompanion`
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

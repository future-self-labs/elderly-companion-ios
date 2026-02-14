# Noah - Elderly Companion: Project Log

Last updated: 2026-02-14

---

## Systems Architecture

```
+-------------------------------------------------------------+
|                        Noah Platform                         |
+-------------------------------------------------------------+
|                                                              |
|  +-------------------+       +----------------------------+ |
|  |   iOS App          |       |  Backend API (Railway)     | |
|  |   (Swift/SwiftUI)  |------>|  Hono + Drizzle + Postgres | |
|  |   elderly-companion|       |  server/ in this repo      | |
|  |   -ios/            |       +----------------------------+ |
|  +-------------------+              |         |              |
|          |                          |         |              |
|          |  LiveKit WebSocket       |         |              |
|          v                          v         v              |
|  +-------------------+   +-----------+  +-----------+       |
|  | LiveKit Cloud      |   | Twilio    |  | Zep Cloud |       |
|  | (Real-time voice)  |   | (SMS/OTP  |  | (Memory)  |       |
|  +-------------------+   |  + calls)  |  +-----------+       |
|          ^                +-----------+                      |
|          |                                                   |
|  +-------------------+                                       |
|  | LiveKit Agent      |                                      |
|  | (Python worker)    |                                      |
|  | elderly-livekit-   |                                      |
|  | server-python/     |                                      |
|  +-------------------+                                       |
|                                                              |
|  +-------------------+                                       |
|  | Marketing Website  |                                      |
|  | (React/Vite)       |                                      |
|  | noah-family-voice/ |                                      |
|  +-------------------+                                       |
+-------------------------------------------------------------+
```

### Repositories

| Repo | Path | Purpose | Deployment |
|------|------|---------|------------|
| **elderly-companion-ios** | `/Users/vincentlindeboom/Projects/Noah/elderly-companion-ios/` | iOS native app (Swift/SwiftUI) + Backend API (TypeScript) | App Store / Railway |
| **elderly-livekit-server-python** | `/Users/vincentlindeboom/Projects/Noah/elderly-livekit-server-python/` | LiveKit voice agent "Noah" (Python) | Railway |
| **noah-family-voice** | `/Users/vincentlindeboom/Projects/Noah/noah-family-voice/` | Marketing landing page (React/Vite) | Render/Vercel |

### Deleted Repos

| Repo | Reason |
|------|--------|
| **elderly-companion** (React Native/Expo) | Replaced by native iOS app. Deleted 2026-02-14. Remote still exists at `github.com/future-self-labs/elderly-companion`. |

---

## elderly-companion-ios - Directory Structure

```
ElderlyCompanion/
  App/
    ElderlyCompanionApp.swift        # @main entry point
    AppState.swift                    # @Observable: isOnboardingComplete, currentUser, isAuthenticated
    RootView.swift                    # Routes to MainTabView or OnboardingContainerView
    MainTabView.swift                 # 4 tabs: Home, Calendar, Memories, Settings
  Core/
    Models/
      User.swift                      # User, UserProfile, CalendarAccessLevel, NotificationPreferences
      Call.swift                      # CallRecord, CallDirection, CallTag
      Reminder.swift                  # Medication, DailyCheckIn, WeeklyRitual
      Memory.swift                    # MemoryEntry, MemoryTag
    Network/
      APIClient.swift                 # Actor-based API client, all endpoints, Bearer JWT auth
    Services/
      AuthService.swift               # @Observable, sendOTP(), validateOTP(), stores JWT in Keychain
      KeychainService.swift           # Static Keychain CRUD for auth token
      LiveKitService.swift            # @Observable, LiveKit room connection, mic, transcription
      CalendarService.swift           # EKEventStore wrapper
      NotificationService.swift       # UNUserNotificationCenter wrapper
  Features/
    Home/
      HomeView.swift                  # Main screen: Talk Now, Call Noah, mood, reminders
      HomeViewModel.swift             # Loads reminders and recent conversation context
    Conversation/
      ConversationView.swift          # Full-screen voice UI with animated orb
      ConversationViewModel.swift     # LiveKit session, timer, transcript, saves on end
    Onboarding/
      OnboardingContainerView.swift   # Step machine: welcome -> profile -> phone -> calendar -> notifs -> legacy -> complete
      WelcomeView.swift               # Landing: "Set up for myself" / "Set up for my parent"
      ProfileCreationView.swift       # Name, nickname, city, phone, proactive calls toggle
      PhoneVerificationView.swift     # Auto-sends OTP, 6-digit input, verify button
      CalendarPermissionView.swift    # Full/ReadOnly/None calendar access
      NotificationPreferencesView.swift # Call/push/SMS toggles, quiet hours
      LegacyPreferencesView.swift     # Life story capture, audio storage, family sharing
    Routines/
      ScheduledCallsView.swift        # List/add scheduled calls (medication, check-in, chat)
      ScheduledCallsViewModel.swift   # CRUD via API
      RoutinesView.swift              # Medications, daily check-ins, weekly rituals
      RoutinesViewModel.swift         # Local persistence via UserDefaults
    Calendar/
      CompanionCalendarView.swift     # Month/Agenda views, add events
    CallHistory/
      CallHistoryView.swift           # Empty state (TODO: fetch from backend)
      CallHistoryViewModel.swift
    Legacy/
      LegacyArchiveView.swift         # Audio/Transcripts/Timeline/Starred
    Activity/
      ActivityOverviewView.swift      # Stats grid + weekly summary placeholder
    Family/
      FamilySettingsView.swift        # Add family member (TODO)
    Safety/
      SafetyView.swift                # Scam protection, escalation rules
      EscalationView.swift            # Trusted contacts, GP/emergency
    Privacy/
      PrivacyView.swift               # GDPR, consent, data info
    AISettings/
      AISettingsView.swift            # Tone, proactive level, call frequency
      AIMemoryView.swift              # Download history, clear memory
    Settings/
      SettingsHubView.swift           # Hub for all settings. Sign out button.
      ThemePickerView.swift           # Calm vs Apple theme selection
  Shared/
    Theme/
      Theme.swift                     # AppTheme enum, ThemeManager, design tokens, colors, typography
    Components/
      CalmCard.swift                  # Reusable card component
      MoodSelector.swift              # Mood enum with emoji/label selector
      LargeButton.swift               # Primary/secondary/outline/danger button

server/
  src/
    index.ts                          # Hono app entry, route mounting, middleware, scheduler start
    middleware/
      auth.ts                         # JWT sign/verify, Hono auth middleware
    lib/
      twilio.ts                       # Twilio client singleton
      livekit.ts                      # LiveKit token generation + SIP outbound calls
      zep.ts                          # Zep memory client singleton
    db/
      schema.ts                       # Drizzle schema: users, transcripts, scheduledCalls
      index.ts                        # PostgreSQL pool + Drizzle instance
    routes/
      otp.ts                          # POST /otp/create (send SMS), POST /otp/validate (verify + JWT)
      livekit.ts                      # POST /livekit/get-token, POST /livekit/call
      users.ts                        # POST /users (create), GET /users/:id, GET /users/search
      memory.ts                       # GET /memory/:userId (Zep context), POST /memory
      transcripts.ts                  # POST /transcripts, GET /transcripts/:userId
      scheduled-calls.ts              # Full CRUD + DB-driven 60s scheduler
  drizzle.config.ts                   # Migration config
  package.json                        # Dependencies: hono, drizzle-orm, pg, twilio, livekit-server-sdk, jsonwebtoken, zep
  Dockerfile                          # Railway deployment
  railway.json                        # Railway config
```

---

## Tech Stack

### iOS App
- **Swift 5.10**, iOS 17+ deployment target
- **SwiftUI** with `@Observable` macro (no Combine)
- **XcodeGen** (`project.yml`) generates the Xcode project
- **LiveKit client-sdk-swift 2.0+** for real-time voice
- Two themes: "Calm" (sage green, warm) and "Apple" (glass morphism, system blue)

### Backend API (server/)
- **Hono** (HTTP framework) on **Node.js** via **tsx**
- **Drizzle ORM** + **PostgreSQL** (Railway addon)
- **Twilio** (SMS OTP via Verify, phone calls)
- **LiveKit Server SDK** (token generation, SIP outbound calls)
- **Zep Cloud** (conversation memory)
- **JWT** (jsonwebtoken) for auth
- Deployed on **Railway** at `https://elderly-companion-api-production.up.railway.app/api/v1`

### LiveKit Agent (elderly-livekit-server-python/)
- **Python 3.13** with **uv** package manager
- **livekit-agents ~1.1.4** (OpenAI Realtime, Silero VAD, server-side turn detection)
- **Zep Cloud** for long-term memory
- Agent name: `"noah"`, dispatch rule: rooms prefixed `call-`
- Two agents: CompanionAgent (main), OnboardingAgent (family info gathering)
- Language: Dutch (Whisper STT)

---

## Database Schema (Drizzle)

### users
| Column | Type | Notes |
|--------|------|-------|
| id | UUID | PK, auto-generated |
| name | TEXT | NOT NULL |
| nickname | TEXT | nullable |
| birth_year | INTEGER | nullable |
| city | TEXT | nullable |
| phone_number | TEXT | NOT NULL, UNIQUE |
| type | TEXT | default "elderly" |
| proactive_calls_enabled | BOOLEAN | default true |
| created_at | TIMESTAMP | default now() |

### transcripts
| Column | Type | Notes |
|--------|------|-------|
| id | UUID | PK, auto-generated |
| user_id | UUID | FK -> users.id |
| duration | INTEGER | seconds, default 0 |
| messages | JSONB | array of {role, content, timestamp} |
| tags | JSONB | array of strings |
| summary | TEXT | nullable |
| created_at | TIMESTAMP | default now() |

### scheduled_calls
| Column | Type | Notes |
|--------|------|-------|
| id | UUID | PK, auto-generated |
| user_id | UUID | FK -> users.id |
| phone_number | TEXT | NOT NULL |
| type | TEXT | default "custom" |
| title | TEXT | NOT NULL |
| message | TEXT | nullable |
| time | TEXT | HH:MM format |
| days | JSONB | array of ints 0-6 (Sun-Sat) |
| enabled | BOOLEAN | default true |
| created_at | TIMESTAMP | default now() |

---

## API Routes

### Public (no auth)
| Method | Path | Description |
|--------|------|-------------|
| GET | /health | Health check |
| POST | /otp/create | Send OTP SMS via Twilio Verify |
| POST | /otp/validate | Verify OTP, return JWT + userId |
| POST | /users | Create user (also used by LiveKit agent) |
| GET | /users/:id | Get user by ID (auto-creates stub if not found) |
| GET | /users/search?phoneNumber= | Search user by phone |
| GET | /memory/:userId | Get Zep memory context |
| POST | /memory | Store memory in Zep |

### Protected (JWT required)
| Method | Path | Description |
|--------|------|-------------|
| POST | /livekit/get-token | Get LiveKit room token |
| POST | /livekit/call | Initiate outbound phone call via SIP |
| POST | /transcripts | Save conversation transcript |
| GET | /transcripts/:userId | Get user's transcripts |
| POST | /scheduled-calls | Create scheduled call |
| GET | /scheduled-calls/:userId | Get user's scheduled calls |
| POST | /scheduled-calls/:id | Update scheduled call |
| DELETE | /scheduled-calls/:id | Delete scheduled call |

---

## Environment Variables

### server/.env
```
PORT=3000
DATABASE_URL=""               # <-- REQUIRED: PostgreSQL connection string
JWT_SECRET=""                 # <-- REQUIRED: Secret for signing JWTs
TWILIO_ACCOUNT_SID=""
TWILIO_AUTH_TOKEN=""
TWILIO_PHONE_NUMBER=""
TWILIO_VERIFY_SERVICE_SID=""
LIVEKIT_API_KEY=""
LIVEKIT_API_SECRET=""
LIVEKIT_URL=""
ZEP_API_KEY=""
AGENT_NAME="noah"
SIP_TRUNK_ID=""
```

### elderly-livekit-server-python/.env
```
API_URL=""                    # Backend API URL
LIVEKIT_API_KEY=""
LIVEKIT_API_SECRET=""
LIVEKIT_URL=""
OPENAI_API_KEY=""
ZEP_API_KEY=""
N8N_API_KEY=""                # Optional
N8N_URL=""                    # Optional
PERPLEXITY_API_KEY=""         # Optional
```

---

## Authentication Flow

```
iOS App                          Backend API                    Twilio
   |                                 |                            |
   |-- POST /otp/create ----------->|                            |
   |   { phoneNumber }              |-- verify.create() -------->|
   |                                |<-- sid, status ------------|
   |<-- { message, status, sid } ---|                            |
   |                                |                            |
   | (user enters 6-digit code)     |                            |
   |                                |                            |
   |-- POST /otp/validate -------->|                            |
   |   { phoneNumber, code }        |-- verificationChecks() --->|
   |                                |<-- status: "approved" -----|
   |                                |                            |
   |                                |-- DB: find/create user     |
   |                                |-- JWT: sign token          |
   |                                |                            |
   |<-- { userId, token } ---------|                            |
   |                                |                            |
   | Store userId -> UserDefaults   |                            |
   | Store token -> Keychain        |                            |
   |                                |                            |
   | All subsequent requests:       |                            |
   |   Authorization: Bearer <jwt>  |                            |
```

---

## Onboarding Flow (iOS)

1. **WelcomeView** - "Set up for myself" / "Set up for my parent"
2. **ProfileCreationView** - Name, nickname, city, phone number, proactive calls toggle
3. **PhoneVerificationView** - Auto-sends OTP, user enters 6-digit code, verifies
4. **CalendarPermissionView** - Full / Read-only / None
5. **NotificationPreferencesView** - Call, push, SMS toggles + quiet hours
6. **LegacyPreferencesView** - Life story, audio storage, family sharing
7. **Complete** - Creates user on backend, sets `appState.isAuthenticated = true`

---

## Production Readiness Plan - Status

### Phase 1: Database -- DONE
- Drizzle ORM + PostgreSQL (Railway addon)
- Three tables: users, transcripts, scheduled_calls
- All routes rewritten to use DB instead of in-memory Maps

### Phase 2: Authentication -- DONE
- JWT-based auth with Twilio Verify OTP
- Keychain storage on iOS (not UserDefaults)
- Auth middleware on protected routes
- OTP routes are public, LiveKit/transcripts/scheduled-calls require JWT

### Phase 3: Persistent Scheduler -- DONE
- Single 60s interval queries scheduled_calls table
- Matches current time + day, triggers outbound calls via LiveKit SIP
- Survives server restarts (schedule lives in DB)

### Phase 4: Cleanup & Hardening -- MOSTLY DONE
Items completed (2026-02-14):
- [x] Fix OTP validation bug -- separate Twilio/DB/JWT errors
- [x] Fix duplicate user bug -- POST /users now updates existing stub
- [x] Fix HTTP method mismatch -- updateScheduledCall uses PUT
- [x] Surface transcript save failure in ConversationViewModel
- [x] CallHistoryView wired to real transcript data from backend
- [x] Error alerts on CallHistoryView
Items remaining:
- [ ] FamilySettingsView: implement add family member
- [ ] ActivityOverviewView: real data instead of placeholders

---

## Known Bugs

### BUG: "Failed to validate OTP" during onboarding
- **Status**: FIXED (2026-02-14)
- **File**: `server/src/routes/otp.ts`
- **What was wrong**: Single catch block caught ALL errors (Twilio, database, JWT) with one generic "Failed to validate OTP" message. Twilio verification succeeded but the DB lookup failed because `DATABASE_URL` was not configured.
- **What was fixed**: Split into 3 separate try/catch blocks (Twilio, database, JWT) with specific error messages. Added `DATABASE_URL` and `JWT_SECRET` to `server/.env`.
- **Remaining**: You still need to set a real `DATABASE_URL` in `.env` (see "What YOU need to do" section).

### BUG: Onboarding creates duplicate/stub user
- **Status**: FIXED (2026-02-14)
- **File**: `server/src/routes/users.ts`
- **What was wrong**: OTP validation created a stub user (`name: "User"`). Then onboarding's `POST /users` found the stub by phone number and returned it as-is. Profile data (name, nickname, city, etc.) was silently discarded.
- **What was fixed**: `POST /users` now UPDATES the existing user with the full profile data when a matching phone number is found, instead of returning the stub.

### BUG: HTTP method mismatch for scheduled call updates
- **Status**: FIXED (2026-02-14)
- **File**: `APIClient.swift`
- **What was wrong**: iOS `updateScheduledCall` used POST, but server expects PUT. Updates silently failed.
- **What was fixed**: Added `put()` and `delete()` methods to APIClient. `updateScheduledCall` now uses PUT. Added `deleteScheduledCall` method.

### BUG: Transcript save failure was silent
- **Status**: FIXED (2026-02-14)
- **Files**: `ConversationViewModel.swift`, `ConversationView.swift`
- **What was wrong**: If saving a transcript after a conversation failed, the error was only logged to console. User had no idea their conversation wasn't saved.
- **What was fixed**: Added `transcriptSaveError` / `showTranscriptSaveError` state + alert in ConversationView.

### BUG: Call history was empty placeholder
- **Status**: FIXED (2026-02-14)
- **Files**: `CallHistoryViewModel.swift`, `CallHistoryView.swift`
- **What was wrong**: `loadCalls()` was a TODO stub returning empty. No error handling.
- **What was fixed**: Now fetches transcripts from backend and converts them to CallRecords. Added error state + alert.

---

## Deployment

### Backend API (Railway)
- **URL**: `https://elderly-companion-api-production.up.railway.app/api/v1`
- **Runtime**: Node.js via tsx (not bun — Railway compatibility)
- **Database**: Railway PostgreSQL addon (auto-provides `DATABASE_URL`)
- **Dockerfile**: Uses `FROM node:20-slim`, installs deps, runs `npx tsx src/index.ts`

### LiveKit Agent (Railway)
- **URL**: Connects to LiveKit Cloud at `wss://test-7hm3rr9r.livekit.cloud`
- **Runtime**: Python 3.13 via uv
- **Agent name**: `"noah"`, dispatch rule: rooms prefixed `call-`

### iOS App
- **Bundle ID**: `com.futureselflabs.elderlycompanion`
- **API URL**: Hardcoded in `APIClient.swift` (`deployedURL` property)
- **Build**: XcodeGen (`project.yml`) -> Xcode -> App Store / TestFlight

---

## What YOU Need To Do (Manual Steps)

### Before the app works end-to-end:
1. **Set `DATABASE_URL` in `server/.env`** -- Point to a real PostgreSQL instance. Options:
   - Local: `postgresql://localhost:5432/noah_dev`
   - Railway: Copy the `DATABASE_URL` from your Railway Postgres addon dashboard
2. **Run database migrations**: `cd server && npm run db:push` (creates the tables)
3. **Set `JWT_SECRET` in Railway env vars** -- Use a strong random string (e.g., `openssl rand -hex 32`)
4. **Verify Railway deployment**: Push server changes and confirm the Railway build succeeds
5. **Test the full onboarding flow** on a real device with a real phone number

### Before payment / subscription / distribution:
6. **Implement StoreKit 2 subscription** -- In-app purchase for monthly/yearly plans
7. **Server-side receipt validation** -- Verify App Store receipts on the backend
8. **Add subscription status to user model** -- New DB column: `subscriptionStatus`, `subscriptionExpiresAt`
9. **Gate features behind subscription** -- Decide which features are free vs. paid
10. **App Store compliance**:
    - Privacy policy URL in app (required by Apple)
    - Data collection disclosures in App Store Connect
    - Review `NSUserTrackingUsageDescription` if using analytics
11. **Localization** -- Currently English UI + Dutch voice agent. For worldwide distribution, localize the iOS app
12. **App Store Connect setup** -- Screenshots, description, keywords, age rating, pricing
13. **TestFlight beta testing** -- Internal + external beta before public release

---

## Key Hardcoded Values
- API URL: `https://elderly-companion-api-production.up.railway.app/api/v1` (APIClient.swift line 51)
- Local fallback: `http://localhost:3000/api/v1` (simulator) or `http://192.168.178.178:3000/api/v1` (device)
- Keychain service: `com.futureselflabs.elderlycompanion` (KeychainService.swift)
- SIP Trunk ID: `ST_FsnpUMR6sYFp` (server/.env.example, used in livekit.ts)
- Agent name: `noah` (server/.env.example)
- JWT expiry: 30 days (auth.ts line 15)
- Scheduler interval: 60 seconds (scheduled-calls.ts)

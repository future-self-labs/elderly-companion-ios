# Noah - Elderly Companion

**Calm. Dignified. Always There.**

A voice-first AI companion for elderly people, reachable via phone call or native iOS app.

## Architecture

```
iOS App (SwiftUI)  ──────►  Backend API (Hono/Bun)  ──────►  LiveKit Cloud
                                    │                              │
                                    ├──► Twilio (OTP, phone)       │
                                    ├──► Zep (memory)         SIP Trunk
                                    │                              │
                              Phone Number  ◄──────────────  Twilio SIP
```

## Project Structure

- `ElderlyCompanion/` - Native iOS app (Swift/SwiftUI, iOS 17+)
- `server/` - Backend API (TypeScript, Hono, Bun)

## Getting Started

### iOS App

1. Generate the Xcode project:

```bash
brew install xcodegen  # if not installed
xcodegen generate
```

2. Open `ElderlyCompanion.xcodeproj` in Xcode
3. Wait for Swift Package Manager to resolve LiveKit SDK
4. Build and run on simulator or device

### Backend API

1. Install dependencies:

```bash
cd server
bun install
```

2. Set up environment variables:

```bash
cp .env.example .env
# Fill in your Twilio + LiveKit + Zep credentials
```

3. Start the development server:

```bash
bun dev
```

The API will be running at `http://localhost:3000/api/v1`.

## Environment Variables

| Variable | Description |
|---|---|
| `TWILIO_ACCOUNT_SID` | Twilio account SID |
| `TWILIO_AUTH_TOKEN` | Twilio auth token |
| `TWILIO_PHONE_NUMBER` | Twilio phone number (the number users call) |
| `TWILIO_VERIFY_SERVICE_SID` | Twilio Verify service SID (for OTP) |
| `LIVEKIT_API_KEY` | LiveKit Cloud API key |
| `LIVEKIT_API_SECRET` | LiveKit Cloud API secret |
| `LIVEKIT_URL` | LiveKit Cloud WebSocket URL |
| `ZEP_API_KEY` | Zep Cloud API key (memory layer) |

## API Endpoints

| Method | Path | Description |
|---|---|---|
| `POST` | `/api/v1/otp/create` | Send OTP to phone number |
| `POST` | `/api/v1/otp/validate` | Validate OTP code |
| `POST` | `/api/v1/livekit/get-token` | Get LiveKit token for in-app voice |
| `POST` | `/api/v1/livekit/call` | Initiate outbound phone call |
| `POST` | `/api/v1/users` | Create user |
| `GET` | `/api/v1/users/:id` | Get user |
| `GET` | `/api/v1/users/search?phoneNumber=` | Search user by phone |
| `GET` | `/api/v1/memory/:userId` | Get user memory context |
| `POST` | `/api/v1/memory` | Store conversation messages |

## Reused from Existing Setup

This project reuses the same credentials and infrastructure:
- Same Twilio account, phone number, and Verify service
- Same LiveKit Cloud project and SIP trunk (`ST_FsnpUMR6sYFp`)
- Same Zep Cloud memory layer

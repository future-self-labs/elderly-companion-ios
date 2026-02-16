import { config } from "dotenv";
config(); // Load .env before anything else

import { Hono } from "hono";
import { cors } from "hono/cors";
import { logger } from "hono/logger";
import { serve } from "@hono/node-server";

import { authMiddleware } from "./middleware/auth";
import { otpRoutes } from "./routes/otp";
import { livekitRoutes } from "./routes/livekit";
import { userRoutes } from "./routes/users";
import { memoryRoutes } from "./routes/memory";
import { transcriptRoutes } from "./routes/transcripts";
import { scheduledCallRoutes, startScheduler } from "./routes/scheduled-calls";
import { familyRoutes } from "./routes/family";
import { healthRoutes } from "./routes/health";
import { peopleRoutes } from "./routes/people";
import { eventRoutes } from "./routes/events";
import { legacyStoryRoutes } from "./routes/legacy-stories";
import { wellbeingRoutes } from "./routes/wellbeing";

const app = new Hono().basePath("/api/v1");

// Middleware
app.use("*", cors());
app.use("*", logger());

// Health check (public)
app.get("/health", (c) => c.json({ status: "ok", timestamp: new Date().toISOString() }));

// Public routes (no auth required)
app.route("/otp", otpRoutes);

// Protected routes (auth required)
// Note: The LiveKit agent also calls /users/* internally, so we allow
// unauthenticated access to user routes for now (agent doesn't have JWT).
// In production, add a separate service-to-service auth token.
app.route("/users", userRoutes);
app.route("/memory", memoryRoutes);

// Routes requiring JWT auth
app.use("/livekit/*", authMiddleware);
app.use("/transcripts/*", authMiddleware);
app.use("/scheduled-calls/*", authMiddleware);
app.route("/livekit", livekitRoutes);
app.route("/transcripts", transcriptRoutes);
app.route("/scheduled-calls", scheduledCallRoutes);
app.route("/family", familyRoutes);
app.route("/health-data", healthRoutes);

// Memory Vault routes (people, events, stories, wellbeing)
// Accessible by elderly users, family members, and caretakers
app.route("/people", peopleRoutes);
app.route("/events", eventRoutes);
app.route("/legacy-stories", legacyStoryRoutes);
app.route("/wellbeing", wellbeingRoutes);

// Start server
const port = Number(process.env.PORT) || 3000;

console.log(`Elderly Companion API running on http://0.0.0.0:${port}`);

serve({
  fetch: app.fetch,
  port,
  hostname: "0.0.0.0",
});

// Start the DB-driven scheduler for proactive calls
if (process.env.DATABASE_URL) {
  startScheduler();
}

export default app;

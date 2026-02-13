import { Hono } from "hono";
import { cors } from "hono/cors";
import { logger } from "hono/logger";
import { serve } from "@hono/node-server";

import { otpRoutes } from "./routes/otp";
import { livekitRoutes } from "./routes/livekit";
import { userRoutes } from "./routes/users";
import { memoryRoutes } from "./routes/memory";

const app = new Hono().basePath("/api/v1");

// Middleware
app.use("*", cors());
app.use("*", logger());

// Health check
app.get("/health", (c) => c.json({ status: "ok", timestamp: new Date().toISOString() }));

// Routes
app.route("/otp", otpRoutes);
app.route("/livekit", livekitRoutes);
app.route("/users", userRoutes);
app.route("/memory", memoryRoutes);

// Start server
const port = Number(process.env.PORT) || 3000;

console.log(`Elderly Companion API running on port ${port}`);

serve({
  fetch: app.fetch,
  port,
});

export default app;

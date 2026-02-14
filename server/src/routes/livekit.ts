import { Hono } from "hono";
import { generateTokenAndDispatch, initiateOutboundCall } from "../lib/livekit";

const app = new Hono();

/**
 * POST /livekit/get-token
 * Generate a LiveKit access token for in-app voice sessions.
 */
app.post("/get-token", async (c) => {
  const { userId } = await c.req.json<{ userId: string }>();

  if (!userId) {
    return c.json({ error: "User ID is required" }, 400);
  }

  try {
    const { token } = await generateTokenAndDispatch(userId);
    return c.json({ token, userId });
  } catch (error) {
    console.error("Error generating token:", error);
    return c.json({ error: "Failed to generate token" }, 500);
  }
});

/**
 * POST /livekit/call
 * Initiate an outbound phone call via Twilio SIP trunk -> LiveKit.
 * This calls the user's phone number and connects them with the AI agent.
 */
app.post("/call", async (c) => {
  const { phoneNumber, userId, message } = await c.req.json<{
    phoneNumber: string;
    userId: string;
    message?: string;
  }>();

  if (!phoneNumber) {
    return c.json({ error: "Phone number is required" }, 400);
  }

  if (!userId) {
    return c.json({ error: "User ID is required" }, 400);
  }

  try {
    const participant = await initiateOutboundCall(phoneNumber, userId, message);
    return c.json({ participant });
  } catch (error) {
    console.error("Error initiating call:", error);
    return c.json({ error: "Failed to initiate call" }, 500);
  }
});

export { app as livekitRoutes };

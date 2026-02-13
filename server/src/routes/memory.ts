import { Hono } from "hono";
import { getZepClient } from "../lib/zep";

const app = new Hono();

/**
 * GET /memory/:userId
 * Retrieve the user's conversation context from Zep memory.
 */
app.get("/:userId", async (c) => {
  const userId = c.req.param("userId");

  try {
    const zep = getZepClient();
    const sessions = await zep.user.getSessions(userId);

    if (!sessions || sessions.length === 0) {
      return c.json({ context: null });
    }

    // Sort by creation date and get the most recent
    const sorted = [...sessions].sort(
      (a, b) =>
        new Date(b.createdAt ?? 0).getTime() -
        new Date(a.createdAt ?? 0).getTime()
    );
    const mostRecent = sorted[0];

    if (!mostRecent.sessionId) {
      return c.json({ context: null });
    }

    const memory = await zep.memory.get(mostRecent.sessionId);

    return c.json({
      context: memory.context || null,
    });
  } catch (error) {
    console.error("Error fetching memory:", error);
    return c.json({ context: null });
  }
});

/**
 * POST /memory
 * Store conversation messages in Zep memory.
 */
app.post("/", async (c) => {
  const { userId, sessionId, messages } = await c.req.json<{
    userId: string;
    sessionId: string;
    messages: Array<{ role: string; content: string }>;
  }>();

  if (!userId || !sessionId || !messages) {
    return c.json({ error: "userId, sessionId, and messages are required" }, 400);
  }

  try {
    const zep = getZepClient();

    // Add messages to the session
    await zep.memory.add(sessionId, {
      messages: messages.map((msg) => ({
        roleType: msg.role === "user" ? "user" : "assistant",
        content: msg.content,
      })),
    });

    return c.json({ message: "Messages stored successfully" });
  } catch (error) {
    console.error("Error storing memory:", error);
    return c.json({ error: "Failed to store messages" }, 500);
  }
});

export { app as memoryRoutes };

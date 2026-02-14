import { Hono } from "hono";
import { eq } from "drizzle-orm";
import { db } from "../db";
import { familyContacts, users, transcripts } from "../db/schema";
import { getTwilioClient } from "../lib/twilio";
import { getZepClient } from "../lib/zep";
import { getHealthSummary } from "./health";

const app = new Hono();

/**
 * POST /family
 * Add a family contact for a user.
 */
app.post("/", async (c) => {
  const body = await c.req.json<{
    userId: string;
    name: string;
    phoneNumber: string;
    relationship: string;
    whatsappUpdatesEnabled?: boolean;
  }>();

  if (!body.userId || !body.name || !body.phoneNumber) {
    return c.json({ error: "userId, name, and phoneNumber are required" }, 400);
  }

  try {
    const [contact] = await db
      .insert(familyContacts)
      .values({
        userId: body.userId,
        name: body.name,
        phoneNumber: body.phoneNumber,
        relationship: body.relationship || "family",
        whatsappUpdatesEnabled: body.whatsappUpdatesEnabled ?? true,
      })
      .returning();

    return c.json(contact, 201);
  } catch (error) {
    console.error("Error adding family contact:", error);
    return c.json({ error: "Failed to add family contact" }, 500);
  }
});

/**
 * GET /family/:userId
 * Get all family contacts for a user.
 */
app.get("/:userId", async (c) => {
  const userId = c.req.param("userId");

  try {
    const contacts = await db
      .select()
      .from(familyContacts)
      .where(eq(familyContacts.userId, userId));

    return c.json({ familyContacts: contacts });
  } catch (error) {
    console.error("Error fetching family contacts:", error);
    return c.json({ familyContacts: [] });
  }
});

/**
 * DELETE /family/:id
 * Remove a family contact.
 */
app.delete("/:id", async (c) => {
  const id = c.req.param("id");

  try {
    await db.delete(familyContacts).where(eq(familyContacts.id, id));
    return c.json({ message: "Deleted" });
  } catch (error) {
    console.error("Error deleting family contact:", error);
    return c.json({ error: "Failed to delete" }, 500);
  }
});

/**
 * POST /family/test-update/:userId
 * Manually trigger a daily update for testing.
 */
app.post("/test-update/:userId", async (c) => {
  const userId = c.req.param("userId");

  try {
    const count = await sendDailyFamilyUpdate(userId);
    return c.json({ message: `Sent updates to ${count} family member(s)` });
  } catch (error: any) {
    console.error("Error sending test update:", error);
    return c.json({ error: error.message || "Failed to send update" }, 500);
  }
});

// MARK: - WhatsApp Daily Update Logic

/**
 * Build a daily summary for the elderly user.
 * Gathers data from transcripts (today's calls) and Zep memory (context).
 */
async function buildDailySummary(userId: string, userName: string): Promise<string> {
  const today = new Date();
  today.setHours(0, 0, 0, 0);

  // Get today's transcripts
  let todaysTranscripts: any[] = [];
  try {
    const allTranscripts = await db
      .select()
      .from(transcripts)
      .where(eq(transcripts.userId, userId));

    todaysTranscripts = allTranscripts.filter((t) => {
      const created = new Date(t.createdAt);
      return created >= today;
    });
  } catch (e) {
    console.error("[DailyUpdate] Error fetching transcripts:", e);
  }

  // Get memory context from Zep
  let memoryContext: string | null = null;
  try {
    const zep = getZepClient();
    const sessions = await zep.user.getSessions(userId);
    if (sessions && sessions.length > 0) {
      const sorted = [...sessions].sort(
        (a, b) =>
          new Date(b.createdAt ?? 0).getTime() -
          new Date(a.createdAt ?? 0).getTime()
      );
      if (sorted[0].sessionId) {
        const memory = await zep.memory.get(sorted[0].sessionId);
        memoryContext = memory.context || null;
      }
    }
  } catch (e) {
    console.error("[DailyUpdate] Error fetching Zep memory:", e);
  }

  // Build the summary
  const dateStr = today.toLocaleDateString("nl-NL", {
    weekday: "long",
    day: "numeric",
    month: "long",
    timeZone: "Europe/Amsterdam",
  });

  const callCount = todaysTranscripts.length;
  const totalMinutes = todaysTranscripts.reduce(
    (sum, t) => sum + Math.round((t.duration || 0) / 60),
    0
  );

  let summary = `🌿 *Noah - Dagelijks overzicht voor ${userName}*\n`;
  summary += `📅 ${dateStr}\n\n`;

  if (callCount > 0) {
    summary += `📞 *${callCount} gesprek${callCount > 1 ? "ken" : ""}* vandaag (${totalMinutes} min totaal)\n\n`;

    // Add summaries from transcripts
    for (const t of todaysTranscripts.slice(0, 3)) {
      const messages = (t.messages as any[]) || [];
      const duration = Math.round((t.duration || 0) / 60);
      if (t.summary) {
        summary += `• ${t.summary} (${duration} min)\n`;
      } else if (messages.length > 0) {
        // Use first assistant message as summary
        const firstAssistant = messages.find((m: any) => m.role === "assistant");
        if (firstAssistant) {
          const snippet = firstAssistant.content.substring(0, 80);
          summary += `• ${snippet}... (${duration} min)\n`;
        }
      }
    }
  } else {
    summary += `📞 Geen gesprekken vandaag\n`;
  }

  summary += `\n`;

  // Add health stats if available
  try {
    const healthSummary = await getHealthSummary(userId);
    if (healthSummary) {
      summary += `${healthSummary}\n\n`;
    }
  } catch (e) {
    console.error("[DailyUpdate] Error fetching health summary:", e);
  }

  // Add mood/context from Zep if available
  if (memoryContext) {
    const contextSnippet = memoryContext.substring(0, 300);
    summary += `💭 *Hoe het gaat:*\n${contextSnippet}\n\n`;
  }

  summary += `_Verstuurd door Noah AI Companion_`;

  return summary;
}

/**
 * Send a WhatsApp daily update to all family contacts for a user.
 * Returns the number of messages sent.
 */
export async function sendDailyFamilyUpdate(userId: string): Promise<number> {
  // Get the elderly user
  const [user] = await db
    .select()
    .from(users)
    .where(eq(users.id, userId))
    .limit(1);

  if (!user) {
    console.log(`[DailyUpdate] User ${userId} not found`);
    return 0;
  }

  // Get family contacts with WhatsApp enabled
  const contacts = await db
    .select()
    .from(familyContacts)
    .where(eq(familyContacts.userId, userId));

  const whatsappContacts = contacts.filter((c) => c.whatsappUpdatesEnabled);

  if (whatsappContacts.length === 0) {
    console.log(`[DailyUpdate] No WhatsApp contacts for user ${userId}`);
    return 0;
  }

  // Build the summary
  const summary = await buildDailySummary(userId, user.name);

  // Send via Twilio WhatsApp
  const twilio = getTwilioClient();
  const fromNumber = `whatsapp:${process.env.TWILIO_WHATSAPP_NUMBER || process.env.TWILIO_PHONE_NUMBER}`;
  let sentCount = 0;

  for (const contact of whatsappContacts) {
    try {
      await twilio.messages.create({
        body: summary,
        from: fromNumber,
        to: `whatsapp:${contact.phoneNumber}`,
      });
      console.log(`[DailyUpdate] Sent WhatsApp to ${contact.name} (${contact.phoneNumber})`);
      sentCount++;
    } catch (error: any) {
      console.error(`[DailyUpdate] Failed to send to ${contact.name}:`, error.message);
    }
  }

  return sentCount;
}

export { app as familyRoutes };

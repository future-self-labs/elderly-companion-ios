import { Hono } from "hono";
import { eq, and } from "drizzle-orm";
import { db } from "../db";
import { scheduledCalls, users, familyContacts } from "../db/schema";
import { initiateOutboundCall } from "../lib/livekit";
import { sendDailyFamilyUpdate } from "./family";
import { runSilenceMonitor, updateAllBaselines } from "../lib/care-engine";

const app = new Hono();

/**
 * POST /scheduled-calls
 * Create a new scheduled/recurring call.
 */
app.post("/", async (c) => {
  const body = await c.req.json<{
    userId: string;
    phoneNumber: string;
    type: string;
    title: string;
    message?: string;
    time: string;
    days: number[];
    enabled: boolean;
  }>();

  if (!body.userId || !body.phoneNumber || !body.time) {
    return c.json({ error: "userId, phoneNumber, and time are required" }, 400);
  }

  try {
    const [call] = await db
      .insert(scheduledCalls)
      .values({
        userId: body.userId,
        phoneNumber: body.phoneNumber,
        type: body.type || "custom",
        title: body.title || "Scheduled call",
        message: body.message || null,
        time: body.time,
        days: body.days?.length ? body.days : [0, 1, 2, 3, 4, 5, 6],
        enabled: body.enabled ?? true,
      })
      .returning();

    return c.json(call, 201);
  } catch (error) {
    console.error("Error creating scheduled call:", error);
    return c.json({ error: "Failed to create scheduled call" }, 500);
  }
});

/**
 * GET /scheduled-calls/:userId
 * Get all scheduled calls for a user.
 */
app.get("/:userId", async (c) => {
  const userId = c.req.param("userId");

  try {
    const calls = await db
      .select()
      .from(scheduledCalls)
      .where(eq(scheduledCalls.userId, userId));

    return c.json({ scheduledCalls: calls });
  } catch (error) {
    console.error("Error fetching scheduled calls:", error);
    return c.json({ scheduledCalls: [] });
  }
});

/**
 * PUT /scheduled-calls/:id
 * Update a scheduled call.
 */
app.put("/:id", async (c) => {
  const id = c.req.param("id");
  const updates = await c.req.json();

  try {
    const [updated] = await db
      .update(scheduledCalls)
      .set(updates)
      .where(eq(scheduledCalls.id, id))
      .returning();

    if (!updated) {
      return c.json({ error: "Scheduled call not found" }, 404);
    }

    return c.json(updated);
  } catch (error) {
    console.error("Error updating scheduled call:", error);
    return c.json({ error: "Failed to update" }, 500);
  }
});

/**
 * DELETE /scheduled-calls/:id
 * Delete a scheduled call.
 */
app.delete("/:id", async (c) => {
  const id = c.req.param("id");

  try {
    await db.delete(scheduledCalls).where(eq(scheduledCalls.id, id));
    return c.json({ message: "Deleted" });
  } catch (error) {
    console.error("Error deleting scheduled call:", error);
    return c.json({ error: "Failed to delete" }, 500);
  }
});

// MARK: - Persistent Scheduler (DB-driven)

function getCallMessage(call: { type: string; title: string; message: string | null }): string {
  switch (call.type) {
    case "medication":
      return `You are calling the user to remind them to take their medication: ${call.title}. Be gentle and caring. Ask if they've taken it and if they need any help.`;
    case "checkin":
      return `You are calling the user for their daily check-in. Ask how they are feeling today, how they slept, and if there's anything on their mind. Be warm and attentive.`;
    case "chat":
      return call.message
        ? `You are calling the user for a friendly chat. The topic for today is: ${call.message}. Keep it light, engaging, and fun.`
        : `You are calling the user for a friendly afternoon chat. Talk about interesting news, ask about their day, or share a fun fact. Keep it warm and engaging.`;
    default:
      return call.message || `You are calling the user for: ${call.title}. Be helpful and friendly.`;
  }
}

/**
 * Get the current time in the user's timezone (Europe/Amsterdam).
 * Railway servers run in UTC, but users are in CET/CEST.
 */
function getAmsterdamTime(): { day: number; time: string } {
  const now = new Date();
  const amsterdamStr = now.toLocaleString("en-US", { timeZone: "Europe/Amsterdam" });
  const amsterdam = new Date(amsterdamStr);
  return {
    day: amsterdam.getDay(),
    time: `${String(amsterdam.getHours()).padStart(2, "0")}:${String(amsterdam.getMinutes()).padStart(2, "0")}`,
  };
}

/**
 * Start the persistent scheduler.
 * Runs every 60 seconds, queries the DB for calls matching the current time/day.
 * Uses Europe/Amsterdam timezone to match user's local time.
 */
export function startScheduler() {
  console.log("[Scheduler] Starting DB-driven scheduler (checks every 60s, timezone: Europe/Amsterdam)");

  // Log initial check to confirm scheduler is alive
  const { day, time } = getAmsterdamTime();
  console.log(`[Scheduler] Current Amsterdam time: ${time}, day: ${day}`);

  setInterval(async () => {
    try {
      const { day: currentDay, time: currentTime } = getAmsterdamTime();

      // Get all enabled calls for the current time
      const calls = await db
        .select()
        .from(scheduledCalls)
        .where(
          and(
            eq(scheduledCalls.enabled, true),
            eq(scheduledCalls.time, currentTime)
          )
        );

      if (calls.length > 0) {
        console.log(`[Scheduler] ${currentTime} Amsterdam - Found ${calls.length} call(s) matching this minute`);
      }

      for (const call of calls) {
        // Check if today is one of the scheduled days
        const days = call.days as number[];
        if (!days.includes(currentDay)) {
          console.log(`[Scheduler] Skipping "${call.title}" - day ${currentDay} not in [${days}]`);
          continue;
        }

        console.log(`[Scheduler] Triggering: "${call.title}" for ${call.phoneNumber}`);

        try {
          await initiateOutboundCall(
            call.phoneNumber,
            call.userId,
            getCallMessage(call)
          );
        } catch (err: any) {
          console.error(`[Scheduler] Call failed for ${call.title}:`, err.message);
        }
      }
      // Daily WhatsApp update - send at 20:00 Amsterdam time
      if (currentTime === "20:00") {
        console.log("[Scheduler] 20:00 - Running daily WhatsApp family updates");
        try {
          // Get all users who have family contacts
          const allUsers = await db.select().from(users);
          for (const user of allUsers) {
            const contacts = await db
              .select()
              .from(familyContacts)
              .where(eq(familyContacts.userId, user.id));

            if (contacts.some((c) => c.whatsappUpdatesEnabled)) {
              try {
                const count = await sendDailyFamilyUpdate(user.id);
                if (count > 0) {
                  console.log(`[Scheduler] Sent daily update for ${user.name} to ${count} contact(s)`);
                }
              } catch (err: any) {
                console.error(`[Scheduler] Daily update failed for ${user.name}:`, err.message);
              }
            }
          }
        } catch (err: any) {
          console.error("[Scheduler] Error running daily WhatsApp updates:", err.message);
        }
      }

      // Silence monitor — run every hour (at :00)
      if (currentTime.endsWith(":00")) {
        try {
          await runSilenceMonitor();
        } catch (err: any) {
          console.error("[Scheduler] Silence monitor error:", err.message);
        }
      }

      // Baseline updater — run once daily at 23:00
      if (currentTime === "23:00") {
        try {
          await updateAllBaselines();
        } catch (err: any) {
          console.error("[Scheduler] Baseline update error:", err.message);
        }
      }
    } catch (error) {
      console.error("[Scheduler] Error checking scheduled calls:", error);
    }
  }, 60_000);
}

export { app as scheduledCallRoutes };

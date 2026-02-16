import { Hono } from "hono";
import { eq, and, gte, lte, sql } from "drizzle-orm";
import { db } from "../db";
import { events, people } from "../db/schema";

const app = new Hono();

/**
 * POST /events
 * Create an event (birthday, anniversary, appointment, etc.)
 */
app.post("/", async (c) => {
  const body = await c.req.json<{
    elderlyUserId: string;
    personId?: string;
    type: string;
    title: string;
    date: string; // ISO date
    recurring?: boolean;
    remindDaysBefore?: number;
  }>();

  if (!body.elderlyUserId || !body.title || !body.date) {
    return c.json({ error: "elderlyUserId, title, and date are required" }, 400);
  }

  try {
    const [event] = await db
      .insert(events)
      .values({
        elderlyUserId: body.elderlyUserId,
        personId: body.personId || null,
        type: body.type || "custom",
        title: body.title,
        date: body.date,
        recurring: body.recurring ?? false,
        remindDaysBefore: body.remindDaysBefore ?? 3,
      })
      .returning();

    return c.json(event, 201);
  } catch (error) {
    console.error("Error creating event:", error);
    return c.json({ error: "Failed to create event" }, 500);
  }
});

/**
 * GET /events/:elderlyUserId
 * Get all events for the elderly user.
 */
app.get("/:elderlyUserId", async (c) => {
  const elderlyUserId = c.req.param("elderlyUserId");

  try {
    const result = await db
      .select()
      .from(events)
      .where(eq(events.elderlyUserId, elderlyUserId));

    return c.json({ events: result });
  } catch (error) {
    console.error("Error fetching events:", error);
    return c.json({ events: [] });
  }
});

/**
 * GET /events/:elderlyUserId/upcoming
 * Get events in the next N days (default 7) for the elderly user.
 * For recurring events (birthdays), matches month+day regardless of year.
 */
app.get("/:elderlyUserId/upcoming", async (c) => {
  const elderlyUserId = c.req.param("elderlyUserId");
  const daysAhead = parseInt(c.req.query("days") || "7");

  try {
    const allEvents = await db
      .select()
      .from(events)
      .where(eq(events.elderlyUserId, elderlyUserId));

    const now = new Date();
    const upcoming: Array<typeof allEvents[0] & { daysUntil: number }> = [];

    for (const event of allEvents) {
      const eventDate = new Date(event.date);
      let targetDate: Date;

      if (event.recurring) {
        // For recurring events, check this year's occurrence
        targetDate = new Date(now.getFullYear(), eventDate.getMonth(), eventDate.getDate());
        // If already passed this year, check next year
        if (targetDate < now) {
          targetDate = new Date(now.getFullYear() + 1, eventDate.getMonth(), eventDate.getDate());
        }
      } else {
        targetDate = eventDate;
      }

      const diffMs = targetDate.getTime() - now.getTime();
      const diffDays = Math.ceil(diffMs / (1000 * 60 * 60 * 24));

      // Include if within range (including remindDaysBefore buffer)
      if (diffDays >= 0 && diffDays <= daysAhead) {
        upcoming.push({ ...event, daysUntil: diffDays });
      }
    }

    // Sort by closest first
    upcoming.sort((a, b) => a.daysUntil - b.daysUntil);

    return c.json({ events: upcoming });
  } catch (error) {
    console.error("Error fetching upcoming events:", error);
    return c.json({ events: [] });
  }
});

/**
 * DELETE /events/:id
 */
app.delete("/:id", async (c) => {
  const id = c.req.param("id");

  try {
    await db.delete(events).where(eq(events.id, id));
    return c.json({ message: "Deleted" });
  } catch (error) {
    console.error("Error deleting event:", error);
    return c.json({ error: "Failed to delete" }, 500);
  }
});

export { app as eventRoutes };

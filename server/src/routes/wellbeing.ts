import { Hono } from "hono";
import { eq, desc, and } from "drizzle-orm";
import { db } from "../db";
import { wellbeingLogs, transcripts, healthSnapshots } from "../db/schema";

const app = new Hono();

/**
 * POST /wellbeing
 * Log or update today's wellbeing entry.
 * Called by the agent after conversations, or by the scheduler at end of day.
 */
app.post("/", async (c) => {
  const body = await c.req.json<{
    elderlyUserId: string;
    date: string; // ISO date
    moodScore?: number;
    conversationCount?: number;
    conversationMinutes?: number;
    topics?: string[];
    concerns?: string[];
    healthSnapshotId?: string;
  }>();

  if (!body.elderlyUserId || !body.date) {
    return c.json({ error: "elderlyUserId and date are required" }, 400);
  }

  try {
    // Upsert: update if entry exists for this date, create if not
    const existing = await db
      .select()
      .from(wellbeingLogs)
      .where(
        and(
          eq(wellbeingLogs.elderlyUserId, body.elderlyUserId),
          eq(wellbeingLogs.date, body.date)
        )
      )
      .limit(1);

    if (existing.length > 0) {
      const [updated] = await db
        .update(wellbeingLogs)
        .set({
          moodScore: body.moodScore ?? existing[0].moodScore,
          conversationCount: body.conversationCount ?? existing[0].conversationCount,
          conversationMinutes: body.conversationMinutes ?? existing[0].conversationMinutes,
          topics: body.topics ?? existing[0].topics,
          concerns: body.concerns ?? existing[0].concerns,
          healthSnapshotId: body.healthSnapshotId ?? existing[0].healthSnapshotId,
        })
        .where(eq(wellbeingLogs.id, existing[0].id))
        .returning();

      return c.json(updated);
    }

    const [log] = await db
      .insert(wellbeingLogs)
      .values({
        elderlyUserId: body.elderlyUserId,
        date: body.date,
        moodScore: body.moodScore || null,
        conversationCount: body.conversationCount || 0,
        conversationMinutes: body.conversationMinutes || 0,
        topics: body.topics || [],
        concerns: body.concerns || [],
        healthSnapshotId: body.healthSnapshotId || null,
      })
      .returning();

    return c.json(log, 201);
  } catch (error) {
    console.error("Error logging wellbeing:", error);
    return c.json({ error: "Failed to log wellbeing" }, 500);
  }
});

/**
 * GET /wellbeing/:elderlyUserId
 * Get wellbeing logs (most recent first, limit 30 = ~1 month).
 */
app.get("/:elderlyUserId", async (c) => {
  const elderlyUserId = c.req.param("elderlyUserId");
  const limit = parseInt(c.req.query("limit") || "30");

  try {
    const logs = await db
      .select()
      .from(wellbeingLogs)
      .where(eq(wellbeingLogs.elderlyUserId, elderlyUserId))
      .orderBy(desc(wellbeingLogs.date))
      .limit(limit);

    return c.json({ wellbeingLogs: logs });
  } catch (error) {
    console.error("Error fetching wellbeing logs:", error);
    return c.json({ wellbeingLogs: [] });
  }
});

/**
 * GET /wellbeing/:elderlyUserId/summary
 * Get a high-level wellbeing summary for the caretaker dashboard.
 */
app.get("/:elderlyUserId/summary", async (c) => {
  const elderlyUserId = c.req.param("elderlyUserId");

  try {
    const logs = await db
      .select()
      .from(wellbeingLogs)
      .where(eq(wellbeingLogs.elderlyUserId, elderlyUserId))
      .orderBy(desc(wellbeingLogs.date))
      .limit(7); // Last 7 days

    const avgMood = logs.filter((l) => l.moodScore).length > 0
      ? logs.reduce((sum, l) => sum + (l.moodScore || 0), 0) / logs.filter((l) => l.moodScore).length
      : null;

    const totalConversations = logs.reduce((sum, l) => sum + l.conversationCount, 0);
    const totalMinutes = logs.reduce((sum, l) => sum + l.conversationMinutes, 0);

    const allConcerns = logs.flatMap((l) => (l.concerns as string[]) || []);
    const allTopics = logs.flatMap((l) => (l.topics as string[]) || []);

    // Deduplicate
    const uniqueConcerns = [...new Set(allConcerns)];
    const topTopics = [...new Set(allTopics)].slice(0, 10);

    return c.json({
      summary: {
        period: "7 days",
        averageMoodScore: avgMood ? Math.round(avgMood * 10) / 10 : null,
        totalConversations,
        totalMinutes,
        activeDays: logs.length,
        concerns: uniqueConcerns,
        topTopics: topTopics,
      },
    });
  } catch (error) {
    console.error("Error fetching wellbeing summary:", error);
    return c.json({ summary: null });
  }
});

export { app as wellbeingRoutes };

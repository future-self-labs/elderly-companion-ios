import { Hono } from "hono";
import { eq, desc } from "drizzle-orm";
import { db } from "../db";
import { healthSnapshots } from "../db/schema";

const app = new Hono();

/**
 * POST /health-data
 * Store a health snapshot from the iOS app.
 */
app.post("/", async (c) => {
  const body = await c.req.json<{
    userId: string;
    stepCount?: number;
    heartRate?: number;
    bloodOxygen?: number;
    bloodPressureSystolic?: number;
    bloodPressureDiastolic?: number;
    sleepHours?: string;
  }>();

  if (!body.userId) {
    return c.json({ error: "userId is required" }, 400);
  }

  try {
    const [snapshot] = await db
      .insert(healthSnapshots)
      .values({
        userId: body.userId,
        stepCount: body.stepCount || 0,
        heartRate: body.heartRate || 0,
        bloodOxygen: body.bloodOxygen || 0,
        bloodPressureSystolic: body.bloodPressureSystolic || 0,
        bloodPressureDiastolic: body.bloodPressureDiastolic || 0,
        sleepHours: body.sleepHours || "0",
      })
      .returning();

    return c.json(snapshot, 201);
  } catch (error) {
    console.error("Error storing health snapshot:", error);
    return c.json({ error: "Failed to store health data" }, 500);
  }
});

/**
 * GET /health-data/:userId
 * Get the latest health snapshot for a user.
 */
app.get("/:userId", async (c) => {
  const userId = c.req.param("userId");

  try {
    const [latest] = await db
      .select()
      .from(healthSnapshots)
      .where(eq(healthSnapshots.userId, userId))
      .orderBy(desc(healthSnapshots.createdAt))
      .limit(1);

    return c.json({ healthData: latest || null });
  } catch (error) {
    console.error("Error fetching health data:", error);
    return c.json({ healthData: null });
  }
});

export { app as healthRoutes };

/**
 * Get a formatted health summary string for use in WhatsApp daily updates.
 */
export async function getHealthSummary(userId: string): Promise<string | null> {
  try {
    const [latest] = await db
      .select()
      .from(healthSnapshots)
      .where(eq(healthSnapshots.userId, userId))
      .orderBy(desc(healthSnapshots.createdAt))
      .limit(1);

    if (!latest) return null;

    // Only include if data is from today
    const snapshotDate = new Date(latest.createdAt);
    const now = new Date();
    const isToday = snapshotDate.toDateString() === now.toDateString();
    if (!isToday) return null;

    const parts: string[] = [];

    if (latest.stepCount && latest.stepCount > 0) {
      parts.push(`🚶 ${latest.stepCount.toLocaleString()} stappen`);
    }
    if (latest.heartRate && latest.heartRate > 0) {
      parts.push(`❤️ ${latest.heartRate} bpm hartslag`);
    }
    if (latest.bloodOxygen && latest.bloodOxygen > 0) {
      parts.push(`🫁 ${latest.bloodOxygen}% bloedzuurstof`);
    }
    if (latest.bloodPressureSystolic && latest.bloodPressureSystolic > 0) {
      parts.push(`🩺 ${latest.bloodPressureSystolic}/${latest.bloodPressureDiastolic} bloeddruk`);
    }
    const sleepNum = parseFloat(latest.sleepHours || "0");
    if (sleepNum > 0) {
      parts.push(`😴 ${sleepNum.toFixed(1)} uur slaap`);
    }

    if (parts.length === 0) return null;

    return `🏥 *Gezondheid vandaag:*\n${parts.join("\n")}`;
  } catch (error) {
    console.error("[Health] Error building summary:", error);
    return null;
  }
}

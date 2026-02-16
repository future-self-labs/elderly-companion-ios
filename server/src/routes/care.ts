import { Hono } from "hono";
import { eq, desc, and, gte } from "drizzle-orm";
import { db } from "../db";
import { careSettings, trustedCircle, careEvents, behavioralBaseline } from "../db/schema";

const app = new Hono();

// =========================================================================
// CARE SETTINGS
// =========================================================================

/**
 * GET /care/settings/:elderlyUserId
 */
app.get("/settings/:elderlyUserId", async (c) => {
  const elderlyUserId = c.req.param("elderlyUserId");
  try {
    let [settings] = await db
      .select()
      .from(careSettings)
      .where(eq(careSettings.elderlyUserId, elderlyUserId))
      .limit(1);

    // Auto-create default settings if none exist
    if (!settings) {
      [settings] = await db
        .insert(careSettings)
        .values({ elderlyUserId })
        .returning();
    }

    return c.json({ settings });
  } catch (error) {
    console.error("Error fetching care settings:", error);
    return c.json({ settings: null, error: "Failed to fetch" }, 500);
  }
});

/**
 * PUT /care/settings/:elderlyUserId
 */
app.put("/settings/:elderlyUserId", async (c) => {
  const elderlyUserId = c.req.param("elderlyUserId");
  const updates = await c.req.json();

  try {
    // Upsert
    const existing = await db
      .select()
      .from(careSettings)
      .where(eq(careSettings.elderlyUserId, elderlyUserId))
      .limit(1);

    if (existing.length > 0) {
      const [updated] = await db
        .update(careSettings)
        .set(updates)
        .where(eq(careSettings.elderlyUserId, elderlyUserId))
        .returning();
      return c.json({ settings: updated });
    }

    const [created] = await db
      .insert(careSettings)
      .values({ elderlyUserId, ...updates })
      .returning();
    return c.json({ settings: created }, 201);
  } catch (error) {
    console.error("Error updating care settings:", error);
    return c.json({ error: "Failed to update" }, 500);
  }
});

// =========================================================================
// TRUSTED CIRCLE
// =========================================================================

/**
 * GET /care/trusted-circle/:elderlyUserId
 */
app.get("/trusted-circle/:elderlyUserId", async (c) => {
  const elderlyUserId = c.req.param("elderlyUserId");
  try {
    const contacts = await db
      .select()
      .from(trustedCircle)
      .where(eq(trustedCircle.elderlyUserId, elderlyUserId));
    return c.json({ contacts });
  } catch (error) {
    console.error("Error fetching trusted circle:", error);
    return c.json({ contacts: [] });
  }
});

/**
 * POST /care/trusted-circle/:elderlyUserId
 */
app.post("/trusted-circle/:elderlyUserId", async (c) => {
  const elderlyUserId = c.req.param("elderlyUserId");
  const body = await c.req.json();

  if (!body.name || !body.phoneNumber) {
    return c.json({ error: "name and phoneNumber are required" }, 400);
  }

  try {
    const [contact] = await db
      .insert(trustedCircle)
      .values({
        elderlyUserId,
        name: body.name,
        phoneNumber: body.phoneNumber,
        role: body.role || "family",
        priorityOrder: body.priorityOrder || 1,
        mayReceiveScamAlerts: body.mayReceiveScamAlerts ?? true,
        mayReceiveEmotionalAlerts: body.mayReceiveEmotionalAlerts ?? true,
        mayReceiveSilenceAlerts: body.mayReceiveSilenceAlerts ?? true,
        mayReceiveCognitiveAlerts: body.mayReceiveCognitiveAlerts ?? true,
        mayReceiveRoutineAlerts: body.mayReceiveRoutineAlerts ?? true,
        outreachMethods: body.outreachMethods || ["call", "whatsapp"],
      })
      .returning();
    return c.json(contact, 201);
  } catch (error) {
    console.error("Error adding trusted contact:", error);
    return c.json({ error: "Failed to add contact" }, 500);
  }
});

/**
 * PUT /care/trusted-circle/:id
 */
app.put("/trusted-circle/update/:id", async (c) => {
  const id = c.req.param("id");
  const updates = await c.req.json();
  try {
    const [updated] = await db
      .update(trustedCircle)
      .set(updates)
      .where(eq(trustedCircle.id, id))
      .returning();
    return c.json(updated);
  } catch (error) {
    console.error("Error updating trusted contact:", error);
    return c.json({ error: "Failed to update" }, 500);
  }
});

/**
 * DELETE /care/trusted-circle/:id
 */
app.delete("/trusted-circle/:id", async (c) => {
  const id = c.req.param("id");
  try {
    await db.delete(trustedCircle).where(eq(trustedCircle.id, id));
    return c.json({ message: "Deleted" });
  } catch (error) {
    console.error("Error deleting trusted contact:", error);
    return c.json({ error: "Failed to delete" }, 500);
  }
});

// =========================================================================
// CARE EVENTS (Outreach Log)
// =========================================================================

/**
 * GET /care/events/:elderlyUserId
 */
app.get("/events/:elderlyUserId", async (c) => {
  const elderlyUserId = c.req.param("elderlyUserId");
  const limit = parseInt(c.req.query("limit") || "50");

  try {
    const events = await db
      .select()
      .from(careEvents)
      .where(eq(careEvents.elderlyUserId, elderlyUserId))
      .orderBy(desc(careEvents.createdAt))
      .limit(limit);
    return c.json({ events });
  } catch (error) {
    console.error("Error fetching care events:", error);
    return c.json({ events: [] });
  }
});

/**
 * POST /care/signal
 * Receive a care signal from the agent. This is the main entry point
 * for the care engine — the agent detects a concern and reports it here.
 */
app.post("/signal", async (c) => {
  const body = await c.req.json<{
    elderlyUserId: string;
    triggerCategory: string;
    riskScore: number;
    description: string;
    aiAction?: string;
  }>();

  if (!body.elderlyUserId || !body.triggerCategory) {
    return c.json({ error: "elderlyUserId and triggerCategory required" }, 400);
  }

  try {
    // Import care engine (lazy to avoid circular deps)
    const { evaluateSignal } = await import("../lib/care-engine");
    const result = await evaluateSignal(body);
    return c.json(result, 201);
  } catch (error) {
    console.error("Error processing care signal:", error);
    return c.json({ error: "Failed to process signal" }, 500);
  }
});

/**
 * POST /care/events/:id/resolve
 * Mark an event as resolved or false alarm.
 */
app.post("/events/:id/resolve", async (c) => {
  const id = c.req.param("id");
  const { outcome } = await c.req.json<{ outcome: "resolved" | "false_alarm" }>();

  try {
    const [updated] = await db
      .update(careEvents)
      .set({
        outcome: outcome || "resolved",
        resolvedAt: new Date(),
      })
      .where(eq(careEvents.id, id))
      .returning();
    return c.json(updated);
  } catch (error) {
    console.error("Error resolving event:", error);
    return c.json({ error: "Failed to resolve" }, 500);
  }
});

// =========================================================================
// BEHAVIORAL BASELINE
// =========================================================================

/**
 * GET /care/baseline/:elderlyUserId
 */
app.get("/baseline/:elderlyUserId", async (c) => {
  const elderlyUserId = c.req.param("elderlyUserId");
  try {
    const [baseline] = await db
      .select()
      .from(behavioralBaseline)
      .where(eq(behavioralBaseline.elderlyUserId, elderlyUserId))
      .limit(1);
    return c.json({ baseline: baseline || null });
  } catch (error) {
    console.error("Error fetching baseline:", error);
    return c.json({ baseline: null });
  }
});

export { app as careRoutes };

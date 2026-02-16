import { Hono } from "hono";
import { eq, and } from "drizzle-orm";
import { db } from "../db";
import { people, events } from "../db/schema";

const app = new Hono();

/**
 * POST /people
 * Add a person to the elderly user's memory vault.
 */
app.post("/", async (c) => {
  const body = await c.req.json<{
    elderlyUserId: string;
    addedByUserId?: string;
    name: string;
    nickname?: string;
    relationship: string;
    phoneNumber?: string;
    email?: string;
    birthDate?: string; // ISO date string
    notes?: string;
    photoUrl?: string;
  }>();

  if (!body.elderlyUserId || !body.name) {
    return c.json({ error: "elderlyUserId and name are required" }, 400);
  }

  try {
    const [person] = await db
      .insert(people)
      .values({
        elderlyUserId: body.elderlyUserId,
        addedByUserId: body.addedByUserId || null,
        name: body.name,
        nickname: body.nickname || null,
        relationship: body.relationship || "family",
        phoneNumber: body.phoneNumber || null,
        email: body.email || null,
        birthDate: body.birthDate || null,
        notes: body.notes || null,
        photoUrl: body.photoUrl || null,
      })
      .returning();

    // Auto-create birthday event if birthDate is provided
    if (body.birthDate && person) {
      await db.insert(events).values({
        elderlyUserId: body.elderlyUserId,
        personId: person.id,
        type: "birthday",
        title: `${body.name}'s verjaardag`,
        date: body.birthDate,
        recurring: true,
        remindDaysBefore: 3,
      });
    }

    return c.json(person, 201);
  } catch (error) {
    console.error("Error adding person:", error);
    return c.json({ error: "Failed to add person" }, 500);
  }
});

/**
 * GET /people/:elderlyUserId
 * Get all people in the elderly user's network.
 */
app.get("/:elderlyUserId", async (c) => {
  const elderlyUserId = c.req.param("elderlyUserId");

  try {
    const result = await db
      .select()
      .from(people)
      .where(eq(people.elderlyUserId, elderlyUserId));

    return c.json({ people: result });
  } catch (error) {
    console.error("Error fetching people:", error);
    return c.json({ people: [] });
  }
});

/**
 * PUT /people/:id
 * Update a person's details.
 */
app.put("/:id", async (c) => {
  const id = c.req.param("id");
  const updates = await c.req.json();

  try {
    const [updated] = await db
      .update(people)
      .set(updates)
      .where(eq(people.id, id))
      .returning();

    if (!updated) {
      return c.json({ error: "Person not found" }, 404);
    }

    return c.json(updated);
  } catch (error) {
    console.error("Error updating person:", error);
    return c.json({ error: "Failed to update" }, 500);
  }
});

/**
 * DELETE /people/:id
 * Remove a person from the vault.
 */
app.delete("/:id", async (c) => {
  const id = c.req.param("id");

  try {
    // Also delete associated events
    await db.delete(events).where(eq(events.personId, id));
    await db.delete(people).where(eq(people.id, id));
    return c.json({ message: "Deleted" });
  } catch (error) {
    console.error("Error deleting person:", error);
    return c.json({ error: "Failed to delete" }, 500);
  }
});

export { app as peopleRoutes };

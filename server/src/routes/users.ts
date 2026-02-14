import { Hono } from "hono";
import { eq } from "drizzle-orm";
import { db } from "../db";
import { users } from "../db/schema";
import { getZepClient } from "../lib/zep";

const app = new Hono();

/**
 * POST /users
 * Create a new user profile.
 */
app.post("/", async (c) => {
  const body = await c.req.json();

  try {
    // Check if user with this phone number already exists
    const existing = await db
      .select()
      .from(users)
      .where(eq(users.phoneNumber, body.phoneNumber))
      .limit(1);

    if (existing.length > 0) {
      return c.json(existing[0]);
    }

    const [user] = await db
      .insert(users)
      .values({
        name: body.name,
        nickname: body.nickname || null,
        birthYear: body.birthYear || null,
        city: body.city || null,
        phoneNumber: body.phoneNumber,
        type: body.type || "elderly",
        proactiveCallsEnabled: body.proactiveCallsEnabled ?? true,
      })
      .returning();

    // Create user in Zep memory store
    try {
      const zep = getZepClient();
      await zep.user.add({ userId: user.id });
    } catch (error) {
      console.error("Error creating Zep user:", error);
    }

    return c.json(user, 201);
  } catch (error) {
    console.error("Error creating user:", error);
    return c.json({ error: "Failed to create user" }, 500);
  }
});

/**
 * GET /users/:id
 * Get a user by ID. Auto-creates a stub if not found (development).
 */
app.get("/:id", async (c) => {
  const id = c.req.param("id");

  try {
    const [user] = await db.select().from(users).where(eq(users.id, id)).limit(1);

    if (!user) {
      // Auto-create stub user so the LiveKit agent doesn't crash
      const [stub] = await db
        .insert(users)
        .values({
          id,
          name: "User",
          phoneNumber: "",
          type: "elderly",
        })
        .returning();

      console.log(`Auto-created stub user: ${id}`);
      return c.json(stub);
    }

    return c.json(user);
  } catch (error) {
    // If the ID isn't a valid UUID, try creating with it as-is
    try {
      const [stub] = await db
        .insert(users)
        .values({
          name: "User",
          phoneNumber: "",
          type: "elderly",
        })
        .onConflictDoNothing()
        .returning();

      if (stub) return c.json(stub);
    } catch {}

    console.error("Error fetching user:", error);
    return c.json({ error: "User not found" }, 404);
  }
});

/**
 * GET /users/search
 * Search for a user by phone number.
 */
app.get("/search", async (c) => {
  const phoneNumber = c.req.query("phoneNumber");

  if (!phoneNumber) {
    return c.json({ error: "Phone number query parameter is required" }, 400);
  }

  try {
    const [user] = await db
      .select()
      .from(users)
      .where(eq(users.phoneNumber, phoneNumber))
      .limit(1);

    if (!user) {
      return c.json({ error: "User not found" }, 404);
    }

    return c.json(user);
  } catch (error) {
    console.error("Error searching user:", error);
    return c.json({ error: "Search failed" }, 500);
  }
});

export { app as userRoutes };

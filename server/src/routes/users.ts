import { Hono } from "hono";
import { v4 as uuidv4 } from "uuid";
import { getZepClient } from "../lib/zep";

const app = new Hono();

// In-memory user store for development
// TODO: Replace with database (SQLite/Postgres)
const users = new Map<string, any>();

/**
 * POST /users
 * Create a new user profile.
 */
app.post("/", async (c) => {
  const body = await c.req.json();

  const user = {
    id: uuidv4(),
    name: body.name,
    nickname: body.nickname || null,
    birthYear: body.birthYear || null,
    city: body.city || null,
    phoneNumber: body.phoneNumber,
    type: body.type || "elderly",
    proactiveCallsEnabled: body.proactiveCallsEnabled ?? true,
    createdAt: new Date().toISOString(),
  };

  users.set(user.id, user);

  // Create user in Zep memory store
  try {
    const zep = getZepClient();
    await zep.user.add({ userId: user.id });
  } catch (error) {
    console.error("Error creating Zep user:", error);
    // Non-fatal: continue even if Zep fails
  }

  return c.json(user, 201);
});

/**
 * GET /users/:id
 * Get a user by ID.
 */
app.get("/:id", async (c) => {
  const id = c.req.param("id");
  const user = users.get(id);

  if (!user) {
    return c.json({ error: "User not found" }, 404);
  }

  return c.json(user);
});

/**
 * GET /users/search?phoneNumber=...
 * Search for a user by phone number.
 */
app.get("/search", async (c) => {
  const phoneNumber = c.req.query("phoneNumber");

  if (!phoneNumber) {
    return c.json({ error: "Phone number query parameter is required" }, 400);
  }

  for (const user of users.values()) {
    if (user.phoneNumber === phoneNumber) {
      return c.json(user);
    }
  }

  return c.json({ error: "User not found" }, 404);
});

export { app as userRoutes };

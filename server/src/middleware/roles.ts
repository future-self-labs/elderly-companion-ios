import { Context, Next } from "hono";
import { eq } from "drizzle-orm";
import { db } from "../db";
import { users } from "../db/schema";

export type Role = "elderly" | "family" | "caretaker";
export type AccessLevel = "full" | "stories_only" | "health_only" | "dashboard_only";

/**
 * Middleware that loads the user's role and access level from the DB
 * and attaches them to the context. Must be used AFTER authMiddleware.
 *
 * Sets: c.get("role"), c.get("accessLevel"), c.get("linkedElderlyId")
 */
export async function roleMiddleware(c: Context, next: Next) {
  const userId = c.get("userId");
  if (!userId) {
    return c.json({ error: "Authentication required" }, 401);
  }

  try {
    const [user] = await db
      .select()
      .from(users)
      .where(eq(users.id, userId))
      .limit(1);

    if (!user) {
      return c.json({ error: "User not found" }, 404);
    }

    c.set("role", user.role || "elderly");
    c.set("accessLevel", user.accessLevel || "full");
    c.set("linkedElderlyId", user.linkedElderlyId || null);
    await next();
  } catch {
    return c.json({ error: "Failed to verify role" }, 500);
  }
}

/**
 * Factory: require one of the given roles.
 */
export function requireRole(...allowedRoles: Role[]) {
  return async (c: Context, next: Next) => {
    const role = c.get("role") as Role;
    if (!allowedRoles.includes(role)) {
      return c.json({ error: "Insufficient permissions" }, 403);
    }
    await next();
  };
}

/**
 * Factory: require one of the given access levels.
 */
export function requireAccess(...allowedLevels: AccessLevel[]) {
  return async (c: Context, next: Next) => {
    const level = c.get("accessLevel") as AccessLevel;
    if (!allowedLevels.includes(level)) {
      return c.json({ error: "Access level insufficient" }, 403);
    }
    await next();
  };
}

/**
 * Resolve the elderly user ID.
 * - If the caller IS elderly, returns their own ID.
 * - If the caller is family/caretaker, returns their linkedElderlyId.
 */
export function resolveElderlyId(c: Context): string | null {
  const role = c.get("role") as Role;
  if (role === "elderly") {
    return c.get("userId") as string;
  }
  return c.get("linkedElderlyId") as string | null;
}

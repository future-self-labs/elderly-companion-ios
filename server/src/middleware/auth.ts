import { Context, Next } from "hono";
import jwt from "jsonwebtoken";

const JWT_SECRET = process.env.JWT_SECRET || "elderly-companion-dev-secret-change-in-production";

export interface JWTPayload {
  userId: string;
  phoneNumber: string;
}

/**
 * Sign a JWT token for a user.
 */
export function signToken(payload: JWTPayload): string {
  return jwt.sign(payload, JWT_SECRET, { expiresIn: "30d" });
}

/**
 * Verify and decode a JWT token.
 */
export function verifyToken(token: string): JWTPayload {
  return jwt.verify(token, JWT_SECRET) as JWTPayload;
}

/**
 * Hono middleware to protect routes with JWT auth.
 * Sets `c.set("userId", ...)` and `c.set("phoneNumber", ...)` on success.
 */
export async function authMiddleware(c: Context, next: Next) {
  const authHeader = c.req.header("Authorization");

  if (!authHeader || !authHeader.startsWith("Bearer ")) {
    return c.json({ error: "Authentication required" }, 401);
  }

  const token = authHeader.slice(7);

  try {
    const payload = verifyToken(token);
    c.set("userId", payload.userId);
    c.set("phoneNumber", payload.phoneNumber);
    await next();
  } catch {
    return c.json({ error: "Invalid or expired token" }, 401);
  }
}

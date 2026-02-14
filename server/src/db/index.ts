import { drizzle } from "drizzle-orm/node-postgres";
import pg from "pg";
import * as schema from "./schema";

const { Pool } = pg;

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: process.env.NODE_ENV === "production" ? { rejectUnauthorized: false } : false,
});

export const db = drizzle(pool, { schema });

// Test connection on startup
pool.query("SELECT 1").then(() => {
  console.log("Database connected");
}).catch((err) => {
  console.error("Database connection failed:", err.message);
});

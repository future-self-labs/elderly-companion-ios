import {
  pgTable,
  text,
  integer,
  boolean,
  timestamp,
  jsonb,
  uuid,
} from "drizzle-orm/pg-core";

export const users = pgTable("users", {
  id: uuid("id").primaryKey().defaultRandom(),
  name: text("name").notNull(),
  nickname: text("nickname"),
  birthYear: integer("birth_year"),
  city: text("city"),
  phoneNumber: text("phone_number").notNull().unique(),
  type: text("type").notNull().default("elderly"),
  proactiveCallsEnabled: boolean("proactive_calls_enabled").notNull().default(true),
  createdAt: timestamp("created_at").notNull().defaultNow(),
});

export const transcripts = pgTable("transcripts", {
  id: uuid("id").primaryKey().defaultRandom(),
  userId: uuid("user_id").notNull().references(() => users.id),
  duration: integer("duration").notNull().default(0),
  messages: jsonb("messages").notNull().default([]),
  tags: jsonb("tags").notNull().default([]),
  summary: text("summary"),
  createdAt: timestamp("created_at").notNull().defaultNow(),
});

export const scheduledCalls = pgTable("scheduled_calls", {
  id: uuid("id").primaryKey().defaultRandom(),
  userId: uuid("user_id").notNull().references(() => users.id),
  phoneNumber: text("phone_number").notNull(),
  type: text("type").notNull().default("custom"),
  title: text("title").notNull(),
  message: text("message"),
  time: text("time").notNull(), // HH:MM format
  days: jsonb("days").notNull().default([0, 1, 2, 3, 4, 5, 6]),
  enabled: boolean("enabled").notNull().default(true),
  createdAt: timestamp("created_at").notNull().defaultNow(),
});

export const familyContacts = pgTable("family_contacts", {
  id: uuid("id").primaryKey().defaultRandom(),
  userId: uuid("user_id").notNull().references(() => users.id),
  name: text("name").notNull(),
  phoneNumber: text("phone_number").notNull(),
  relationship: text("relationship").notNull().default("family"),
  whatsappUpdatesEnabled: boolean("whatsapp_updates_enabled").notNull().default(true),
  createdAt: timestamp("created_at").notNull().defaultNow(),
});

// Type exports for use in routes
export type User = typeof users.$inferSelect;
export type NewUser = typeof users.$inferInsert;
export type Transcript = typeof transcripts.$inferSelect;
export type NewTranscript = typeof transcripts.$inferInsert;
export type ScheduledCall = typeof scheduledCalls.$inferSelect;
export type NewScheduledCall = typeof scheduledCalls.$inferInsert;
export type FamilyContact = typeof familyContacts.$inferSelect;
export type NewFamilyContact = typeof familyContacts.$inferInsert;

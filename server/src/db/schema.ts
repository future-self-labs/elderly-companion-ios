import {
  pgTable,
  text,
  integer,
  boolean,
  timestamp,
  jsonb,
  uuid,
  date,
} from "drizzle-orm/pg-core";

// ---------------------------------------------------------------------------
// Users — elderly users, family members, and caretakers
// ---------------------------------------------------------------------------

export const users = pgTable("users", {
  id: uuid("id").primaryKey().defaultRandom(),
  name: text("name").notNull(),
  nickname: text("nickname"),
  birthYear: integer("birth_year"),
  city: text("city"),
  phoneNumber: text("phone_number").notNull().unique(),
  type: text("type").notNull().default("elderly"), // kept for backward compat
  role: text("role").notNull().default("elderly"), // "elderly" | "family" | "caretaker"
  linkedElderlyId: uuid("linked_elderly_id"), // FK → users.id (which elderly user this person is connected to)
  accessLevel: text("access_level").notNull().default("full"), // "full" | "stories_only" | "health_only" | "dashboard_only"
  notificationsEnabled: boolean("notifications_enabled").notNull().default(true),
  proactiveCallsEnabled: boolean("proactive_calls_enabled").notNull().default(true),
  createdAt: timestamp("created_at").notNull().defaultNow(),
});

// ---------------------------------------------------------------------------
// Transcripts — conversation records
// ---------------------------------------------------------------------------

export const transcripts = pgTable("transcripts", {
  id: uuid("id").primaryKey().defaultRandom(),
  userId: uuid("user_id").notNull().references(() => users.id),
  duration: integer("duration").notNull().default(0),
  messages: jsonb("messages").notNull().default([]),
  tags: jsonb("tags").notNull().default([]),
  summary: text("summary"),
  audioUrl: text("audio_url"), // Supabase Storage URL for conversation audio
  createdAt: timestamp("created_at").notNull().defaultNow(),
});

// ---------------------------------------------------------------------------
// Scheduled Calls — recurring/one-time call reminders
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// Health Snapshots — daily health data from Apple Health
// ---------------------------------------------------------------------------

export const healthSnapshots = pgTable("health_snapshots", {
  id: uuid("id").primaryKey().defaultRandom(),
  userId: uuid("user_id").notNull().references(() => users.id),
  stepCount: integer("step_count").default(0),
  heartRate: integer("heart_rate").default(0),
  bloodOxygen: integer("blood_oxygen").default(0),
  bloodPressureSystolic: integer("blood_pressure_systolic").default(0),
  bloodPressureDiastolic: integer("blood_pressure_diastolic").default(0),
  sleepHours: text("sleep_hours").default("0"),
  createdAt: timestamp("created_at").notNull().defaultNow(),
});

// ---------------------------------------------------------------------------
// Family Contacts — kept for backward compat, gradually replaced by `people`
// ---------------------------------------------------------------------------

export const familyContacts = pgTable("family_contacts", {
  id: uuid("id").primaryKey().defaultRandom(),
  userId: uuid("user_id").notNull().references(() => users.id),
  name: text("name").notNull(),
  phoneNumber: text("phone_number").notNull(),
  relationship: text("relationship").notNull().default("family"),
  whatsappUpdatesEnabled: boolean("whatsapp_updates_enabled").notNull().default(true),
  createdAt: timestamp("created_at").notNull().defaultNow(),
});

// ---------------------------------------------------------------------------
// People — the elderly user's personal network (memory vault)
// Richer than familyContacts: stores birthdays, notes, photos, etc.
// ---------------------------------------------------------------------------

export const people = pgTable("people", {
  id: uuid("id").primaryKey().defaultRandom(),
  elderlyUserId: uuid("elderly_user_id").notNull().references(() => users.id),
  addedByUserId: uuid("added_by_user_id").references(() => users.id),
  name: text("name").notNull(),
  nickname: text("nickname"),
  relationship: text("relationship").notNull().default("family"),
  phoneNumber: text("phone_number"),
  email: text("email"),
  birthDate: date("birth_date"),
  notes: text("notes"),
  photoUrl: text("photo_url"),
  createdAt: timestamp("created_at").notNull().defaultNow(),
});

// ---------------------------------------------------------------------------
// Events — recurring and one-time events to surface in conversations
// ---------------------------------------------------------------------------

export const events = pgTable("events", {
  id: uuid("id").primaryKey().defaultRandom(),
  elderlyUserId: uuid("elderly_user_id").notNull().references(() => users.id),
  personId: uuid("person_id").references(() => people.id),
  type: text("type").notNull().default("custom"), // "birthday" | "anniversary" | "appointment" | "visit" | "custom"
  title: text("title").notNull(),
  date: date("date").notNull(),
  recurring: boolean("recurring").notNull().default(false),
  remindDaysBefore: integer("remind_days_before").notNull().default(3),
  createdAt: timestamp("created_at").notNull().defaultNow(),
});

// ---------------------------------------------------------------------------
// Legacy Stories — life stories captured during conversations
// ---------------------------------------------------------------------------

export const legacyStories = pgTable("legacy_stories", {
  id: uuid("id").primaryKey().defaultRandom(),
  elderlyUserId: uuid("elderly_user_id").notNull().references(() => users.id),
  transcriptId: uuid("transcript_id").references(() => transcripts.id),
  title: text("title").notNull(),
  summary: text("summary"),
  audioUrl: text("audio_url"),
  audioDuration: integer("audio_duration"), // seconds
  tags: jsonb("tags").notNull().default([]),
  peopleMentioned: jsonb("people_mentioned").notNull().default([]), // array of people.id
  isStarred: boolean("is_starred").notNull().default(false),
  createdAt: timestamp("created_at").notNull().defaultNow(),
});

// ---------------------------------------------------------------------------
// Wellbeing Logs — daily tracking for caretaker dashboard
// ---------------------------------------------------------------------------

export const wellbeingLogs = pgTable("wellbeing_logs", {
  id: uuid("id").primaryKey().defaultRandom(),
  elderlyUserId: uuid("elderly_user_id").notNull().references(() => users.id),
  date: date("date").notNull(),
  moodScore: integer("mood_score"), // 1-5 scale
  conversationCount: integer("conversation_count").notNull().default(0),
  conversationMinutes: integer("conversation_minutes").notNull().default(0),
  topics: jsonb("topics").notNull().default([]),
  concerns: jsonb("concerns").notNull().default([]), // flagged concerns
  healthSnapshotId: uuid("health_snapshot_id").references(() => healthSnapshots.id),
  createdAt: timestamp("created_at").notNull().defaultNow(),
});

// ---------------------------------------------------------------------------
// Type exports
// ---------------------------------------------------------------------------

export type User = typeof users.$inferSelect;
export type NewUser = typeof users.$inferInsert;
export type Transcript = typeof transcripts.$inferSelect;
export type NewTranscript = typeof transcripts.$inferInsert;
export type ScheduledCall = typeof scheduledCalls.$inferSelect;
export type NewScheduledCall = typeof scheduledCalls.$inferInsert;
export type FamilyContact = typeof familyContacts.$inferSelect;
export type NewFamilyContact = typeof familyContacts.$inferInsert;
export type HealthSnapshot = typeof healthSnapshots.$inferSelect;
export type NewHealthSnapshot = typeof healthSnapshots.$inferInsert;
export type Person = typeof people.$inferSelect;
export type NewPerson = typeof people.$inferInsert;
export type Event = typeof events.$inferSelect;
export type NewEvent = typeof events.$inferInsert;
export type LegacyStory = typeof legacyStories.$inferSelect;
export type NewLegacyStory = typeof legacyStories.$inferInsert;
export type WellbeingLog = typeof wellbeingLogs.$inferSelect;
export type NewWellbeingLog = typeof wellbeingLogs.$inferInsert;
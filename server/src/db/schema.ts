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
// Care Settings — per-elderly care configuration (optional feature)
// ---------------------------------------------------------------------------

export const careSettings = pgTable("care_settings", {
  id: uuid("id").primaryKey().defaultRandom(),
  elderlyUserId: uuid("elderly_user_id").notNull().references(() => users.id).unique(),
  careEnabled: boolean("care_enabled").notNull().default(false),
  sensitivity: text("sensitivity").notNull().default("balanced"), // "conservative" | "balanced" | "protective"
  silenceWindowHours: integer("silence_window_hours").notNull().default(48),
  cognitiveDriftThreshold: integer("cognitive_drift_threshold").notNull().default(5),
  scamThreshold: text("scam_threshold").notNull().default("medium"), // "low" | "medium" | "high"
  aiFirstContact: boolean("ai_first_contact").notNull().default(true),
  maxOutreachPerWeek: integer("max_outreach_per_week").notNull().default(3),
  escalationCooldownHours: integer("escalation_cooldown_hours").notNull().default(24),
  createdAt: timestamp("created_at").notNull().defaultNow(),
});

// ---------------------------------------------------------------------------
// Trusted Circle — enhanced contacts with per-category alert permissions
// ---------------------------------------------------------------------------

export const trustedCircle = pgTable("trusted_circle", {
  id: uuid("id").primaryKey().defaultRandom(),
  elderlyUserId: uuid("elderly_user_id").notNull().references(() => users.id),
  name: text("name").notNull(),
  phoneNumber: text("phone_number").notNull(),
  role: text("role").notNull().default("family"), // "family" | "caretaker" | "neighbor" | "friend"
  priorityOrder: integer("priority_order").notNull().default(1),
  mayReceiveScamAlerts: boolean("may_receive_scam_alerts").notNull().default(true),
  mayReceiveEmotionalAlerts: boolean("may_receive_emotional_alerts").notNull().default(true),
  mayReceiveSilenceAlerts: boolean("may_receive_silence_alerts").notNull().default(true),
  mayReceiveCognitiveAlerts: boolean("may_receive_cognitive_alerts").notNull().default(true),
  mayReceiveRoutineAlerts: boolean("may_receive_routine_alerts").notNull().default(true),
  outreachMethods: jsonb("outreach_methods").notNull().default(["call", "whatsapp"]),
  isActive: boolean("is_active").notNull().default(true),
  createdAt: timestamp("created_at").notNull().defaultNow(),
});

// ---------------------------------------------------------------------------
// Care Events — every detection, attempt, and outcome logged
// ---------------------------------------------------------------------------

export const careEvents = pgTable("care_events", {
  id: uuid("id").primaryKey().defaultRandom(),
  elderlyUserId: uuid("elderly_user_id").notNull().references(() => users.id),
  triggerCategory: text("trigger_category").notNull(), // cognitive_drift | emotional | scam | silence | medication | help_request | environmental
  riskScore: integer("risk_score").notNull().default(1), // 1-10
  escalationLayer: integer("escalation_layer").notNull().default(0), // 0-4
  description: text("description"),
  aiAction: text("ai_action"),
  aiContactedElderly: boolean("ai_contacted_elderly").notNull().default(false),
  elderlyResponded: boolean("elderly_responded"),
  elderlyResponse: text("elderly_response"),
  externalContactId: uuid("external_contact_id").references(() => trustedCircle.id),
  externalContactMethod: text("external_contact_method"), // "call" | "whatsapp" | "sms"
  outcome: text("outcome").notNull().default("pending"), // "resolved" | "escalated" | "pending" | "false_alarm"
  resolvedAt: timestamp("resolved_at"),
  createdAt: timestamp("created_at").notNull().defaultNow(),
});

// ---------------------------------------------------------------------------
// Behavioral Baseline — rolling behavioral profile for anomaly detection
// ---------------------------------------------------------------------------

export const behavioralBaseline = pgTable("behavioral_baseline", {
  id: uuid("id").primaryKey().defaultRandom(),
  elderlyUserId: uuid("elderly_user_id").notNull().references(() => users.id).unique(),
  avgDailyConversations: integer("avg_daily_conversations").default(0),
  avgMoodScore: integer("avg_mood_score").default(0), // stored as x10 (e.g. 35 = 3.5)
  avgConversationMinutes: integer("avg_conversation_minutes").default(0),
  lastInteraction: timestamp("last_interaction"),
  typicalActiveHours: jsonb("typical_active_hours").notNull().default([]),
  knownConcerns: jsonb("known_concerns").notNull().default([]),
  updatedAt: timestamp("updated_at").notNull().defaultNow(),
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
export type CareSetting = typeof careSettings.$inferSelect;
export type NewCareSetting = typeof careSettings.$inferInsert;
export type TrustedCircleContact = typeof trustedCircle.$inferSelect;
export type NewTrustedCircleContact = typeof trustedCircle.$inferInsert;
export type CareEvent = typeof careEvents.$inferSelect;
export type NewCareEvent = typeof careEvents.$inferInsert;
export type BehavioralBaselineRecord = typeof behavioralBaseline.$inferSelect;
export type NewBehavioralBaselineRecord = typeof behavioralBaseline.$inferInsert;
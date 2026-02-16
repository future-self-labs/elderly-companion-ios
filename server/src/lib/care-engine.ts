/**
 * Care Engine — Risk scoring, escalation layers, and outreach execution.
 *
 * This is the brain of the care infrastructure. It receives signals from the
 * agent (via POST /care/signal) and the scheduler (silence monitor), scores
 * them, and executes the appropriate escalation layer.
 *
 * Guiding principles:
 * - Always try the elderly first
 * - Always de-escalate before escalating
 * - Only reach out externally if necessary
 * - Always log every action
 * - Never diagnose, override autonomy, or replace family
 */

import { eq, desc, gte, and } from "drizzle-orm";
import { db } from "../db";
import {
  careSettings,
  careEvents,
  trustedCircle,
  behavioralBaseline,
  wellbeingLogs,
  transcripts,
  users,
} from "../db/schema";
import { getTwilioClient } from "./twilio";
import { initiateOutboundCall } from "./livekit";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

type TriggerCategory =
  | "cognitive_drift"
  | "emotional"
  | "scam"
  | "silence"
  | "medication"
  | "help_request"
  | "environmental";

interface CareSignal {
  elderlyUserId: string;
  triggerCategory: TriggerCategory;
  riskScore: number; // 1-10
  description: string;
  aiAction?: string;
}

// Category severity weights (used in risk calculation)
const CATEGORY_WEIGHTS: Record<TriggerCategory, number> = {
  scam: 1.5,
  help_request: 1.4,
  environmental: 1.3,
  silence: 1.1,
  cognitive_drift: 1.0,
  emotional: 1.0,
  medication: 0.8,
};

// Sensitivity multipliers
const SENSITIVITY_MULTIPLIERS: Record<string, number> = {
  conservative: 0.7,
  balanced: 1.0,
  protective: 1.4,
};

// ---------------------------------------------------------------------------
// Main entry point
// ---------------------------------------------------------------------------

export async function evaluateSignal(signal: CareSignal) {
  const { elderlyUserId } = signal;

  // 1. Load care settings (auto-create if missing)
  const settings = await getOrCreateSettings(elderlyUserId);

  // If care is not enabled, just log at L0 and return
  if (!settings.careEnabled) {
    return logCareEvent(signal, 0, "Care not enabled — observation only");
  }

  // 2. Check cooldown — prevent over-escalation
  const inCooldown = await checkCooldown(elderlyUserId, settings.escalationCooldownHours);
  if (inCooldown && signal.riskScore < 8) {
    console.log(`[CareEngine] In cooldown for ${elderlyUserId}, suppressing (risk=${signal.riskScore})`);
    return logCareEvent(signal, 0, "Suppressed — within cooldown period");
  }

  // 3. Check weekly cap
  const weeklyCount = await getWeeklyOutreachCount(elderlyUserId);
  const atCap = weeklyCount >= settings.maxOutreachPerWeek;

  // 4. Calculate adjusted risk score
  const sensitivityMultiplier = SENSITIVITY_MULTIPLIERS[settings.sensitivity] || 1.0;
  const categoryWeight = CATEGORY_WEIGHTS[signal.triggerCategory] || 1.0;
  const adjustedRisk = Math.min(10, Math.round(signal.riskScore * categoryWeight * sensitivityMultiplier));

  // 5. Determine escalation layer
  let layer = determineLayer(adjustedRisk, settings);

  // 5b. Multi-signal requirement for L3+ (unless critical severity >= 8)
  // Prevents single-event overreaction — need at least 2 signals in 48h for L3+
  if (layer >= 3 && signal.riskScore < 8) {
    const recentSignalCount = await getRecentSignalCount(elderlyUserId, 48);
    if (recentSignalCount < 2) {
      console.log(`[CareEngine] Downgrading L${layer} to L2 — only ${recentSignalCount} signal(s) in 48h (need 2+)`);
      layer = 2;
    }
  }

  // 5c. Check for recent false alarms — reduce sensitivity if family flagged false alarm recently
  const recentFalseAlarms = await getRecentFalseAlarmCount(elderlyUserId, 7 * 24); // past week
  if (recentFalseAlarms > 0 && layer >= 2 && signal.riskScore < 7) {
    console.log(`[CareEngine] ${recentFalseAlarms} false alarm(s) this week — downgrading L${layer} to L${layer - 1}`);
    layer = Math.max(0, layer - 1);
  }

  console.log(`[CareEngine] Signal: ${signal.triggerCategory}, raw=${signal.riskScore}, adjusted=${adjustedRisk}, layer=L${layer}`);

  // 6. Execute escalation
  if (layer === 0) {
    return logCareEvent(signal, 0, "Observed and logged — no action needed");
  }

  if (layer === 1) {
    // Gentle clarification — call the elderly
    const event = await logCareEvent(signal, 1, "Gentle clarification — attempting to contact elderly");
    await attemptElderlyContact(elderlyUserId, signal, event.id);
    return event;
  }

  if (layer === 2) {
    // Confirmed outreach — AI asks elderly, then contacts trusted circle if confirmed
    const event = await logCareEvent(signal, 2, "Confirmed outreach — will ask elderly for permission");
    await attemptElderlyContact(elderlyUserId, signal, event.id);
    return event;
  }

  if (layer === 3 && !atCap) {
    // Soft protective — try elderly first, then contact trusted circle
    const event = await logCareEvent(signal, 3, "Soft protective — contacting elderly, will escalate if no response");
    await attemptElderlyContact(elderlyUserId, signal, event.id);
    // Schedule a follow-up check (the silence monitor will handle this)
    return event;
  }

  if (layer === 4 || (layer >= 3 && signal.riskScore >= 8)) {
    // Critical safeguard — contact trusted circle directly
    const event = await logCareEvent(signal, 4, "Critical safeguard — contacting trusted circle");
    if (!atCap) {
      await contactTrustedCircle(elderlyUserId, signal, event.id);
    }
    return event;
  }

  return logCareEvent(signal, 0, "Processed — no escalation triggered");
}

// ---------------------------------------------------------------------------
// Escalation layer determination
// ---------------------------------------------------------------------------

function determineLayer(adjustedRisk: number, settings: any): number {
  // Conservative: higher thresholds
  // Protective: lower thresholds
  const base = settings.sensitivity === "conservative" ? 1 : settings.sensitivity === "protective" ? -1 : 0;

  if (adjustedRisk <= 2 + base) return 0;
  if (adjustedRisk <= 4 + base) return 1;
  if (adjustedRisk <= 6 + base) return 2;
  if (adjustedRisk <= 8 + base) return 3;
  return 4;
}

// ---------------------------------------------------------------------------
// Contact functions
// ---------------------------------------------------------------------------

async function attemptElderlyContact(elderlyUserId: string, signal: CareSignal, eventId: string) {
  try {
    const [user] = await db.select().from(users).where(eq(users.id, elderlyUserId)).limit(1);
    if (!user?.phoneNumber) return;

    const message = buildElderlyMessage(signal);

    await initiateOutboundCall(user.phoneNumber, elderlyUserId, message);

    await db.update(careEvents).set({ aiContactedElderly: true }).where(eq(careEvents.id, eventId));
    console.log(`[CareEngine] Called elderly ${user.name} about ${signal.triggerCategory}`);
  } catch (error) {
    console.error("[CareEngine] Failed to contact elderly:", error);
  }
}

async function contactTrustedCircle(elderlyUserId: string, signal: CareSignal, eventId: string) {
  try {
    // Get contacts matching this trigger category, sorted by priority
    const contacts = await db
      .select()
      .from(trustedCircle)
      .where(and(eq(trustedCircle.elderlyUserId, elderlyUserId), eq(trustedCircle.isActive, true)));

    const eligible = contacts
      .filter((c) => isContactEligible(c, signal.triggerCategory))
      .sort((a, b) => a.priorityOrder - b.priorityOrder);

    if (eligible.length === 0) {
      console.log(`[CareEngine] No eligible contacts for ${signal.triggerCategory}`);
      return;
    }

    // Get the elderly user's name
    const [user] = await db.select().from(users).where(eq(users.id, elderlyUserId)).limit(1);
    const elderlyName = user?.name || "uw naaste";

    // Contact the highest-priority eligible person
    const contact = eligible[0];
    const methods = (contact.outreachMethods as string[]) || ["whatsapp"];

    for (const method of methods) {
      if (method === "whatsapp" || method === "sms") {
        await sendOutreachMessage(contact, elderlyName, signal, method);
        await db.update(careEvents).set({
          externalContactId: contact.id,
          externalContactMethod: method,
          outcome: "escalated",
        }).where(eq(careEvents.id, eventId));
        console.log(`[CareEngine] Sent ${method} to ${contact.name} about ${signal.triggerCategory}`);
        return; // One method per escalation
      }
    }
  } catch (error) {
    console.error("[CareEngine] Failed to contact trusted circle:", error);
  }
}

// ---------------------------------------------------------------------------
// Message builders (Dutch, gentle tone)
// ---------------------------------------------------------------------------

function buildElderlyMessage(signal: CareSignal): string {
  switch (signal.triggerCategory) {
    case "silence":
      return "Noah heeft gemerkt dat jullie al even niet gesproken hebben. Even checken hoe het gaat.";
    case "medication":
      return "Noah wil even checken of alles goed gaat met de medicijnen.";
    case "emotional":
      return "Noah wilde even bijpraten. Er is geen haast, gewoon een gezellig gesprekje.";
    default:
      return "Noah wilde even contact opnemen. Niets ernstigs, gewoon even checken hoe het gaat.";
  }
}

const OUTREACH_TEMPLATES: Record<string, (elderlyName: string, desc: string) => string> = {
  cognitive_drift: (name, desc) =>
    `Hoi, Noah hier. Ik heb de afgelopen dagen een paar keer gemerkt dat ${name} wat verward was over data en afspraken. Niets ernstigs, maar ik wilde het even laten weten. Misschien even bellen?`,
  emotional: (name) =>
    `Hoi, Noah hier. ${name} leek de laatste dagen wat stiller en somberder dan gebruikelijk. Even een belletje kan veel doen.`,
  scam: (name) =>
    `Hoi, Noah hier. ${name} beschreef een verdacht telefoontje. Ik heb geholpen, maar het is goed om even te checken.`,
  silence: (name) =>
    `Hoi, Noah hier. Ik heb ${name} al een tijdje niet gesproken, terwijl dat normaal wel zo is. Kun je even checken of alles goed gaat?`,
  medication: (name) =>
    `Hoi, Noah hier. ${name} heeft een paar medicijnherinneringen gemist. Misschien even navragen?`,
  help_request: (name) =>
    `Hoi, Noah hier. ${name} heeft aangegeven hulp nodig te hebben. Kun je zo snel mogelijk contact opnemen?`,
  environmental: (name) =>
    `Hoi, Noah hier. ${name} leek gedesoriënteerd tijdens ons gesprek. Kun je even checken of alles in orde is?`,
};

async function sendOutreachMessage(
  contact: any,
  elderlyName: string,
  signal: CareSignal,
  method: "whatsapp" | "sms"
) {
  const template = OUTREACH_TEMPLATES[signal.triggerCategory] || OUTREACH_TEMPLATES.silence;
  const message = template(elderlyName, signal.description);

  const twilio = getTwilioClient();
  const from = method === "whatsapp"
    ? `whatsapp:${process.env.TWILIO_WHATSAPP_NUMBER || process.env.TWILIO_PHONE_NUMBER}`
    : process.env.TWILIO_PHONE_NUMBER;
  const to = method === "whatsapp" ? `whatsapp:${contact.phoneNumber}` : contact.phoneNumber;

  await twilio.messages.create({ body: message, from: from!, to });
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function isContactEligible(contact: any, category: TriggerCategory): boolean {
  switch (category) {
    case "scam": return contact.mayReceiveScamAlerts;
    case "emotional": return contact.mayReceiveEmotionalAlerts;
    case "silence": return contact.mayReceiveSilenceAlerts;
    case "cognitive_drift": return contact.mayReceiveCognitiveAlerts;
    case "medication": return contact.mayReceiveRoutineAlerts;
    case "help_request": return true; // Always eligible for help requests
    case "environmental": return contact.mayReceiveCognitiveAlerts;
    default: return true;
  }
}

async function getOrCreateSettings(elderlyUserId: string) {
  let [settings] = await db
    .select()
    .from(careSettings)
    .where(eq(careSettings.elderlyUserId, elderlyUserId))
    .limit(1);

  if (!settings) {
    [settings] = await db
      .insert(careSettings)
      .values({ elderlyUserId })
      .returning();
  }
  return settings;
}

async function checkCooldown(elderlyUserId: string, cooldownHours: number): Promise<boolean> {
  const cutoff = new Date(Date.now() - cooldownHours * 60 * 60 * 1000);

  const recentEvents = await db
    .select()
    .from(careEvents)
    .where(
      and(
        eq(careEvents.elderlyUserId, elderlyUserId),
        gte(careEvents.createdAt, cutoff)
      )
    )
    .limit(1);

  return recentEvents.length > 0;
}

async function getWeeklyOutreachCount(elderlyUserId: string): Promise<number> {
  const weekAgo = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000);

  const events = await db
    .select()
    .from(careEvents)
    .where(
      and(
        eq(careEvents.elderlyUserId, elderlyUserId),
        gte(careEvents.createdAt, weekAgo),
        gte(careEvents.escalationLayer, 2)
      )
    );

  return events.length;
}

async function getRecentSignalCount(elderlyUserId: string, hours: number): Promise<number> {
  const cutoff = new Date(Date.now() - hours * 60 * 60 * 1000);
  const events = await db
    .select()
    .from(careEvents)
    .where(
      and(
        eq(careEvents.elderlyUserId, elderlyUserId),
        gte(careEvents.createdAt, cutoff)
      )
    );
  return events.length;
}

async function getRecentFalseAlarmCount(elderlyUserId: string, hours: number): Promise<number> {
  const cutoff = new Date(Date.now() - hours * 60 * 60 * 1000);
  const events = await db
    .select()
    .from(careEvents)
    .where(
      and(
        eq(careEvents.elderlyUserId, elderlyUserId),
        eq(careEvents.outcome, "false_alarm"),
        gte(careEvents.createdAt, cutoff)
      )
    );
  return events.length;
}

async function logCareEvent(signal: CareSignal, layer: number, action: string) {
  const [event] = await db
    .insert(careEvents)
    .values({
      elderlyUserId: signal.elderlyUserId,
      triggerCategory: signal.triggerCategory,
      riskScore: signal.riskScore,
      escalationLayer: layer,
      description: signal.description,
      aiAction: action,
      outcome: layer === 0 ? "resolved" : "pending",
    })
    .returning();

  return event;
}

// ---------------------------------------------------------------------------
// Silence Monitor (called by scheduler)
// ---------------------------------------------------------------------------

export async function runSilenceMonitor() {
  try {
    const allSettings = await db
      .select()
      .from(careSettings)
      .where(eq(careSettings.careEnabled, true));

    for (const settings of allSettings) {
      const [baseline] = await db
        .select()
        .from(behavioralBaseline)
        .where(eq(behavioralBaseline.elderlyUserId, settings.elderlyUserId))
        .limit(1);

      if (!baseline?.lastInteraction) continue;

      const hoursSinceInteraction =
        (Date.now() - new Date(baseline.lastInteraction).getTime()) / (1000 * 60 * 60);

      if (hoursSinceInteraction > settings.silenceWindowHours) {
        console.log(`[SilenceMonitor] ${settings.elderlyUserId} silent for ${Math.round(hoursSinceInteraction)}h (threshold: ${settings.silenceWindowHours}h)`);

        await evaluateSignal({
          elderlyUserId: settings.elderlyUserId,
          triggerCategory: "silence",
          riskScore: Math.min(10, Math.round(hoursSinceInteraction / settings.silenceWindowHours * 5)),
          description: `No interaction for ${Math.round(hoursSinceInteraction)} hours`,
        });
      }
    }
  } catch (error) {
    console.error("[SilenceMonitor] Error:", error);
  }
}

// ---------------------------------------------------------------------------
// Baseline Updater (called by scheduler daily)
// ---------------------------------------------------------------------------

export async function updateAllBaselines() {
  try {
    const allUsers = await db.select().from(users).where(eq(users.role, "elderly"));

    for (const user of allUsers) {
      try {
        // Get last 30 days of wellbeing logs
        const thirtyDaysAgo = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000);
        const logs = await db
          .select()
          .from(wellbeingLogs)
          .where(
            and(
              eq(wellbeingLogs.elderlyUserId, user.id),
              gte(wellbeingLogs.createdAt, thirtyDaysAgo)
            )
          );

        // Get last interaction
        const [lastTranscript] = await db
          .select()
          .from(transcripts)
          .where(eq(transcripts.userId, user.id))
          .orderBy(desc(transcripts.createdAt))
          .limit(1);

        const avgMood = logs.length > 0
          ? Math.round(logs.reduce((sum, l) => sum + (l.moodScore || 0), 0) / logs.filter((l) => l.moodScore).length * 10)
          : 0;
        const avgConversations = logs.length > 0
          ? Math.round(logs.reduce((sum, l) => sum + l.conversationCount, 0) / logs.length)
          : 0;
        const avgMinutes = logs.length > 0
          ? Math.round(logs.reduce((sum, l) => sum + l.conversationMinutes, 0) / logs.length)
          : 0;

        // Upsert baseline
        const existing = await db
          .select()
          .from(behavioralBaseline)
          .where(eq(behavioralBaseline.elderlyUserId, user.id))
          .limit(1);

        const values = {
          elderlyUserId: user.id,
          avgDailyConversations: avgConversations,
          avgMoodScore: avgMood,
          avgConversationMinutes: avgMinutes,
          lastInteraction: lastTranscript?.createdAt || null,
          updatedAt: new Date(),
        };

        if (existing.length > 0) {
          await db.update(behavioralBaseline).set(values).where(eq(behavioralBaseline.elderlyUserId, user.id));
        } else {
          await db.insert(behavioralBaseline).values(values);
        }
      } catch (err) {
        console.error(`[Baseline] Error updating for ${user.id}:`, err);
      }
    }

    console.log("[Baseline] All baselines updated");
  } catch (error) {
    console.error("[Baseline] Error:", error);
  }
}

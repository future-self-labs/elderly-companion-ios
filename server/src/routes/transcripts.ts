import { Hono } from "hono";
import { eq, desc } from "drizzle-orm";
import { db } from "../db";
import { transcripts } from "../db/schema";
import { uploadConversationAudio } from "../lib/supabase";

const app = new Hono();

/**
 * POST /transcripts
 * Save a conversation transcript.
 */
app.post("/", async (c) => {
  const { userId, duration, messages, tags, summary } = await c.req.json<{
    userId: string;
    duration: number;
    messages: Array<{ role: string; content: string; timestamp: string }>;
    tags?: string[];
    summary?: string;
  }>();

  if (!userId || !messages) {
    return c.json({ error: "userId and messages are required" }, 400);
  }

  try {
    const [transcript] = await db
      .insert(transcripts)
      .values({
        userId,
        duration: duration || 0,
        messages,
        tags: tags || ["companion"],
        summary: summary || null,
      })
      .returning();

    return c.json(transcript, 201);
  } catch (error) {
    console.error("Error saving transcript:", error);
    return c.json({ error: "Failed to save transcript" }, 500);
  }
});

/**
 * GET /transcripts/:userId
 * Get all transcripts for a user.
 */
app.get("/:userId", async (c) => {
  const userId = c.req.param("userId");

  try {
    const userTranscripts = await db
      .select()
      .from(transcripts)
      .where(eq(transcripts.userId, userId))
      .orderBy(desc(transcripts.createdAt))
      .limit(50);

    return c.json({ transcripts: userTranscripts });
  } catch (error) {
    console.error("Error fetching transcripts:", error);
    return c.json({ transcripts: [] });
  }
});

/**
 * GET /transcripts/:userId/:transcriptId
 * Get a single transcript.
 */
app.get("/:userId/:transcriptId", async (c) => {
  const transcriptId = c.req.param("transcriptId");

  try {
    const [transcript] = await db
      .select()
      .from(transcripts)
      .where(eq(transcripts.id, transcriptId))
      .limit(1);

    if (!transcript) {
      return c.json({ error: "Transcript not found" }, 404);
    }

    return c.json(transcript);
  } catch (error) {
    console.error("Error fetching transcript:", error);
    return c.json({ error: "Failed to fetch transcript" }, 500);
  }
});

/**
 * POST /transcripts/:transcriptId/audio
 * Upload conversation audio for a transcript.
 * Body: raw audio bytes (Content-Type: audio/webm)
 */
app.post("/:transcriptId/audio", async (c) => {
  const transcriptId = c.req.param("transcriptId");

  try {
    // Get the transcript to find the userId
    const [transcript] = await db
      .select()
      .from(transcripts)
      .where(eq(transcripts.id, transcriptId))
      .limit(1);

    if (!transcript) {
      return c.json({ error: "Transcript not found" }, 404);
    }

    const audioData = await c.req.arrayBuffer();
    const audioUrl = await uploadConversationAudio(
      transcript.userId,
      transcriptId,
      Buffer.from(audioData)
    );

    if (!audioUrl) {
      return c.json({ error: "Failed to upload audio" }, 500);
    }

    // Update transcript with audio URL
    const [updated] = await db
      .update(transcripts)
      .set({ audioUrl })
      .where(eq(transcripts.id, transcriptId))
      .returning();

    return c.json({ audioUrl: updated.audioUrl });
  } catch (error) {
    console.error("Error uploading audio:", error);
    return c.json({ error: "Failed to upload audio" }, 500);
  }
});

export { app as transcriptRoutes };

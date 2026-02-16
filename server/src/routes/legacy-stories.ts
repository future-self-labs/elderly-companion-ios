import { Hono } from "hono";
import { eq, desc } from "drizzle-orm";
import { db } from "../db";
import { legacyStories } from "../db/schema";

const app = new Hono();

/**
 * POST /legacy-stories
 * Create a legacy story record (usually auto-created after a conversation).
 */
app.post("/", async (c) => {
  const body = await c.req.json<{
    elderlyUserId: string;
    transcriptId?: string;
    title: string;
    summary?: string;
    audioUrl?: string;
    audioDuration?: number;
    tags?: string[];
    peopleMentioned?: string[];
    isStarred?: boolean;
  }>();

  if (!body.elderlyUserId || !body.title) {
    return c.json({ error: "elderlyUserId and title are required" }, 400);
  }

  try {
    const [story] = await db
      .insert(legacyStories)
      .values({
        elderlyUserId: body.elderlyUserId,
        transcriptId: body.transcriptId || null,
        title: body.title,
        summary: body.summary || null,
        audioUrl: body.audioUrl || null,
        audioDuration: body.audioDuration || null,
        tags: body.tags || [],
        peopleMentioned: body.peopleMentioned || [],
        isStarred: body.isStarred ?? false,
      })
      .returning();

    return c.json(story, 201);
  } catch (error) {
    console.error("Error creating legacy story:", error);
    return c.json({ error: "Failed to create story" }, 500);
  }
});

/**
 * GET /legacy-stories/:elderlyUserId
 * Get all legacy stories for the elderly user.
 */
app.get("/:elderlyUserId", async (c) => {
  const elderlyUserId = c.req.param("elderlyUserId");

  try {
    const stories = await db
      .select()
      .from(legacyStories)
      .where(eq(legacyStories.elderlyUserId, elderlyUserId))
      .orderBy(desc(legacyStories.createdAt))
      .limit(100);

    return c.json({ stories });
  } catch (error) {
    console.error("Error fetching stories:", error);
    return c.json({ stories: [] });
  }
});

/**
 * PUT /legacy-stories/:id
 * Update a story (e.g., star/unstar, edit title).
 */
app.put("/:id", async (c) => {
  const id = c.req.param("id");
  const updates = await c.req.json();

  try {
    const [updated] = await db
      .update(legacyStories)
      .set(updates)
      .where(eq(legacyStories.id, id))
      .returning();

    if (!updated) {
      return c.json({ error: "Story not found" }, 404);
    }

    return c.json(updated);
  } catch (error) {
    console.error("Error updating story:", error);
    return c.json({ error: "Failed to update" }, 500);
  }
});

/**
 * DELETE /legacy-stories/:id
 */
app.delete("/:id", async (c) => {
  const id = c.req.param("id");

  try {
    await db.delete(legacyStories).where(eq(legacyStories.id, id));
    return c.json({ message: "Deleted" });
  } catch (error) {
    console.error("Error deleting story:", error);
    return c.json({ error: "Failed to delete" }, 500);
  }
});

export { app as legacyStoryRoutes };

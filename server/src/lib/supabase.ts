/**
 * Supabase Storage client for uploading conversation audio and legacy story clips.
 *
 * Buckets:
 * - conversation-audio/{elderlyUserId}/{transcriptId}.webm
 * - legacy-audio/{elderlyUserId}/{storyId}.webm
 *
 * Requires env vars:
 * - SUPABASE_URL
 * - SUPABASE_SERVICE_KEY (service role key for server-side uploads)
 */

const SUPABASE_URL = process.env.SUPABASE_URL || "";
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_KEY || "";

function getHeaders() {
  return {
    Authorization: `Bearer ${SUPABASE_KEY}`,
    apikey: SUPABASE_KEY,
  };
}

/**
 * Upload a file to Supabase Storage.
 */
export async function uploadAudio(
  bucket: string,
  path: string,
  data: Buffer | Uint8Array,
  contentType: string = "audio/webm"
): Promise<string | null> {
  if (!SUPABASE_URL || !SUPABASE_KEY) {
    console.warn("[Supabase] Storage not configured (missing SUPABASE_URL or SUPABASE_SERVICE_KEY)");
    return null;
  }

  const url = `${SUPABASE_URL}/storage/v1/object/${bucket}/${path}`;

  try {
    const response = await fetch(url, {
      method: "POST",
      headers: {
        ...getHeaders(),
        "Content-Type": contentType,
        "x-upsert": "true",
      },
      body: data,
    });

    if (!response.ok) {
      const error = await response.text();
      console.error(`[Supabase] Upload failed: ${response.status} ${error}`);
      return null;
    }

    // Return the public URL
    const publicUrl = `${SUPABASE_URL}/storage/v1/object/public/${bucket}/${path}`;
    console.log(`[Supabase] Uploaded: ${publicUrl}`);
    return publicUrl;
  } catch (error) {
    console.error("[Supabase] Upload error:", error);
    return null;
  }
}

/**
 * Upload conversation audio.
 */
export async function uploadConversationAudio(
  elderlyUserId: string,
  transcriptId: string,
  audioData: Buffer | Uint8Array
): Promise<string | null> {
  return uploadAudio(
    "conversation-audio",
    `${elderlyUserId}/${transcriptId}.webm`,
    audioData
  );
}

/**
 * Upload legacy story audio clip.
 */
export async function uploadLegacyAudio(
  elderlyUserId: string,
  storyId: string,
  audioData: Buffer | Uint8Array
): Promise<string | null> {
  return uploadAudio(
    "legacy-audio",
    `${elderlyUserId}/${storyId}.webm`,
    audioData
  );
}

/**
 * Get a signed URL for temporary access to a private audio file.
 */
export async function getSignedUrl(
  bucket: string,
  path: string,
  expiresIn: number = 3600
): Promise<string | null> {
  if (!SUPABASE_URL || !SUPABASE_KEY) return null;

  const url = `${SUPABASE_URL}/storage/v1/object/sign/${bucket}/${path}`;

  try {
    const response = await fetch(url, {
      method: "POST",
      headers: {
        ...getHeaders(),
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ expiresIn }),
    });

    if (!response.ok) return null;

    const data = await response.json() as { signedURL?: string };
    return data.signedURL ? `${SUPABASE_URL}${data.signedURL}` : null;
  } catch {
    return null;
  }
}

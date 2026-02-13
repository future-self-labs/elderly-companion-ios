import { ZepClient } from "@getzep/zep-cloud";

let client: ZepClient | null = null;

export function getZepClient(): ZepClient {
  const apiKey = process.env.ZEP_API_KEY;
  if (!apiKey) throw new Error("ZEP_API_KEY is not set");

  if (!client) {
    client = new ZepClient({ apiKey });
  }

  return client;
}

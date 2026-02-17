import { AccessToken, SipClient, AgentDispatchClient } from "livekit-server-sdk";
import { v4 as uuidv4 } from "uuid";

function requireEnv(name: string): string {
  const value = process.env[name];
  if (!value) throw new Error(`${name} is not set`);
  return value;
}

function getAgentName(): string {
  return process.env.AGENT_NAME || "noah";
}

function getSipTrunkId(): string {
  return process.env.SIP_TRUNK_ID || "ST_FsnpUMR6sYFp";
}

/**
 * Generate a LiveKit access token for in-app voice sessions
 * and explicitly dispatch the agent to the room.
 */
export async function generateTokenAndDispatch(userId: string): Promise<{ token: string; roomName: string }> {
  const apiKey = requireEnv("LIVEKIT_API_KEY");
  const apiSecret = requireEnv("LIVEKIT_API_SECRET");
  const livekitUrl = requireEnv("LIVEKIT_URL");
  const agentName = getAgentName();

  const roomName = uuidv4();

  const at = new AccessToken(apiKey, apiSecret, {
    identity: userId,
    ttl: "2 hours",
  });

  at.addGrant({
    room: roomName,
    roomJoin: true,
  });

  const token = await at.toJwt();

  // Single explicit dispatch only (no roomConfig — it caused double agents)
  const agentDispatchClient = new AgentDispatchClient(livekitUrl, apiKey, apiSecret);
  await agentDispatchClient.createDispatch(roomName, agentName);

  return { token, roomName };
}

/**
 * Generate a LiveKit access token for in-app voice sessions
 * using the pipeline agent (Deepgram STT + GPT-4o-mini + ElevenLabs TTS).
 */
export async function generatePipelineTokenAndDispatch(userId: string, voiceId?: string): Promise<{ token: string; roomName: string }> {
  const apiKey = requireEnv("LIVEKIT_API_KEY");
  const apiSecret = requireEnv("LIVEKIT_API_SECRET");
  const livekitUrl = requireEnv("LIVEKIT_URL");
  const agentName = getAgentName();

  const roomName = uuidv4();

  // Encode pipeline mode + voice preference in metadata as JSON
  const metadata = JSON.stringify({
    mode: "pipeline",
    voiceId: voiceId || null,
  });

  const at = new AccessToken(apiKey, apiSecret, {
    identity: userId,
    ttl: "2 hours",
  });

  at.addGrant({
    room: roomName,
    roomJoin: true,
  });

  const token = await at.toJwt();

  // Single explicit dispatch only (no roomConfig — it caused double agents)
  const agentDispatchClient = new AgentDispatchClient(livekitUrl, apiKey, apiSecret);
  await agentDispatchClient.createDispatch(roomName, agentName, { metadata });

  return { token, roomName };
}

/**
 * Initiate an outbound phone call via SIP trunk.
 *
 * Room name MUST start with "call-" to match the LiveKit dispatch rule
 * (dispatch-rule.json: roomPrefix "call-"). This ensures the "noah" agent
 * is automatically dispatched when the room is created.
 */
export async function initiateOutboundCall(
  phoneNumber: string,
  userId: string,
  initialRequest?: string
) {
  const livekitUrl = requireEnv("LIVEKIT_URL");
  const apiKey = requireEnv("LIVEKIT_API_KEY");
  const apiSecret = requireEnv("LIVEKIT_API_SECRET");
  const trunkId = getSipTrunkId();
  const agentName = getAgentName();

  const sipClient = new SipClient(livekitUrl, apiKey, apiSecret);
  // Room name must start with "call-" to trigger auto-dispatch of the agent
  const roomName = `call-${userId}`;

  console.log(`[LiveKit] Initiating outbound call: room=${roomName}, phone=${phoneNumber}, userId=${userId}`);

  // Dispatch agent FIRST so it's ready when the phone call connects
  const agentDispatchClient = new AgentDispatchClient(livekitUrl, apiKey, apiSecret);
  await agentDispatchClient.createDispatch(roomName, agentName, {
    metadata: "outbound_call",
  });

  console.log(`[LiveKit] Agent dispatched to room ${roomName}`);

  // Now create the SIP participant (dials the phone number)
  const participant = await sipClient.createSipParticipant(
    trunkId,
    phoneNumber,
    roomName,
    {
      participantIdentity: `sip_${phoneNumber}`,
      participantName: "Caller",
      krispEnabled: true,
      participantAttributes: initialRequest
        ? { initialRequest }
        : undefined,
    }
  );

  console.log(`[LiveKit] SIP participant created in room ${roomName}`);

  return participant;
}

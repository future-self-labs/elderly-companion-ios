import { RoomAgentDispatch, RoomConfiguration } from "@livekit/protocol";
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

  at.roomConfig = new RoomConfiguration({
    agents: [
      new RoomAgentDispatch({ agentName }),
    ],
  });

  const token = await at.toJwt();

  // Also explicitly dispatch the agent
  const agentDispatchClient = new AgentDispatchClient(livekitUrl, apiKey, apiSecret);

  agentDispatchClient.createDispatch(roomName, agentName, {
    metadata: "in_app_voice",
  }).catch((err) => {
    console.log("Agent dispatch (will retry via roomConfig):", err.message);
  });

  return { token, roomName };
}

/**
 * Initiate an outbound phone call via SIP trunk.
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
  const roomName = userId;

  const participant = await sipClient.createSipParticipant(
    trunkId,
    phoneNumber,
    roomName,
    {
      participantIdentity: userId,
      participantName: "Caller",
      krispEnabled: true,
      participantAttributes: initialRequest
        ? { initialRequest }
        : undefined,
    }
  );

  const agentDispatchClient = new AgentDispatchClient(livekitUrl, apiKey, apiSecret);
  await agentDispatchClient.createDispatch(roomName, agentName, {
    metadata: "outbound_call",
  });

  return participant;
}

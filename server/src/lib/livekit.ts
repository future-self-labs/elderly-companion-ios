import { RoomAgentDispatch, RoomConfiguration } from "@livekit/protocol";
import { AccessToken, SipClient, AgentDispatchClient } from "livekit-server-sdk";
import { v4 as uuidv4 } from "uuid";

function requireEnv(name: string): string {
  const value = process.env[name];
  if (!value) throw new Error(`${name} is not set`);
  return value;
}

/**
 * Generate a LiveKit access token for in-app voice sessions.
 * The token grants room join permission and dispatches the "noah" agent.
 */
export async function generateToken(userId: string): Promise<string> {
  const apiKey = requireEnv("LIVEKIT_API_KEY");
  const apiSecret = requireEnv("LIVEKIT_API_SECRET");

  const at = new AccessToken(apiKey, apiSecret, {
    identity: userId,
    ttl: "2 hours",
  });

  at.addGrant({
    room: uuidv4(),
    roomJoin: true,
  });

  at.roomConfig = new RoomConfiguration({
    agents: [
      new RoomAgentDispatch({
        agentName: "noah",
      }),
    ],
  });

  return at.toJwt();
}

/**
 * Initiate an outbound phone call via LiveKit SIP trunk.
 * Uses the existing Twilio SIP trunk (ST_FsnpUMR6sYFp) to call the user.
 */
export async function initiateOutboundCall(
  phoneNumber: string,
  userId: string,
  initialRequest?: string
) {
  const livekitUrl = requireEnv("LIVEKIT_URL");
  const apiKey = requireEnv("LIVEKIT_API_KEY");
  const apiSecret = requireEnv("LIVEKIT_API_SECRET");

  const sipClient = new SipClient(livekitUrl, apiKey, apiSecret);

  // Outbound SIP trunk ID (Twilio <-> LiveKit Cloud)
  const trunkId = "ST_FsnpUMR6sYFp";
  const roomName = userId;

  const participant = await sipClient.createSipParticipant(
    trunkId,
    phoneNumber,
    roomName,
    {
      participantIdentity: userId,
      participantName: "Unknown Caller",
      krispEnabled: true,
      participantAttributes: initialRequest
        ? { initialRequest }
        : undefined,
    }
  );

  // Dispatch the noah agent to the room
  const agentDispatchClient = new AgentDispatchClient(
    livekitUrl,
    apiKey,
    apiSecret
  );

  await agentDispatchClient.createDispatch(roomName, "noah", {
    metadata: "outbound_call",
  });

  return participant;
}

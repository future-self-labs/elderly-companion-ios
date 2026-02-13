import Twilio from "twilio";

let client: Twilio.Twilio | null = null;

export function getTwilioClient(): Twilio.Twilio {
  const accountSid = process.env.TWILIO_ACCOUNT_SID;
  const authToken = process.env.TWILIO_AUTH_TOKEN;

  if (!accountSid) throw new Error("TWILIO_ACCOUNT_SID is not set");
  if (!authToken) throw new Error("TWILIO_AUTH_TOKEN is not set");

  if (!client) {
    client = Twilio(accountSid, authToken);
  }

  return client;
}

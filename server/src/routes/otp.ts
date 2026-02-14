import { Hono } from "hono";
import { eq } from "drizzle-orm";
import { getTwilioClient } from "../lib/twilio";
import { db } from "../db";
import { users } from "../db/schema";
import { signToken } from "../middleware/auth";

const app = new Hono();

/**
 * POST /otp/create
 * Send an OTP code via SMS to the given phone number.
 */
app.post("/create", async (c) => {
  const { phoneNumber } = await c.req.json<{ phoneNumber: string }>();

  if (!phoneNumber) {
    return c.json({ error: "Phone number is required" }, 400);
  }

  const verifyServiceSid = process.env.TWILIO_VERIFY_SERVICE_SID;
  if (!verifyServiceSid) {
    return c.json({ error: "Twilio Verify service not configured" }, 500);
  }

  try {
    const twilio = getTwilioClient();

    const result = await twilio.verify.v2
      .services(verifyServiceSid)
      .verifications.create({
        channel: "sms",
        locale: "en",
        to: phoneNumber,
      });

    return c.json({
      message: "OTP sent successfully",
      status: result.status,
      sid: result.sid,
    });
  } catch (error) {
    console.error("Error sending OTP:", error);
    return c.json({ error: "Failed to send OTP" }, 500);
  }
});

/**
 * POST /otp/validate
 * Validate the OTP code for a given phone number.
 * Returns user ID and JWT token on success.
 */
app.post("/validate", async (c) => {
  const { phoneNumber, code } = await c.req.json<{
    phoneNumber: string;
    code: string;
  }>();

  if (!phoneNumber || !code) {
    return c.json({ error: "Phone number and OTP code are required" }, 400);
  }

  const verifyServiceSid = process.env.TWILIO_VERIFY_SERVICE_SID;
  if (!verifyServiceSid) {
    return c.json({ error: "Twilio Verify service not configured" }, 500);
  }

  try {
    const twilio = getTwilioClient();

    const check = await twilio.verify.v2
      .services(verifyServiceSid)
      .verificationChecks.create({ code, to: phoneNumber });

    if (check.status !== "approved") {
      return c.json({ error: "Invalid OTP" }, 400);
    }

    // Look up or create user by phone number
    let [user] = await db
      .select()
      .from(users)
      .where(eq(users.phoneNumber, phoneNumber))
      .limit(1);

    if (!user) {
      [user] = await db
        .insert(users)
        .values({ name: "User", phoneNumber })
        .returning();
    }

    // Sign JWT
    const token = signToken({
      userId: user.id,
      phoneNumber: user.phoneNumber,
    });

    return c.json({
      message: "OTP validated successfully",
      userId: user.id,
      token,
    });
  } catch (error) {
    console.error("Error validating OTP:", error);
    return c.json({ error: "Failed to validate OTP" }, 500);
  }
});

export { app as otpRoutes };

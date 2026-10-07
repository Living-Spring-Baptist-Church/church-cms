import { z } from "zod";

import { AUTH_COPY } from "@core/copy/auth.copy";
import { TOTP_CODE_LENGTH } from "@core/data/auth.data";

const MAX_EMAIL_LENGTH = 254;
// Supabase rejects longer passwords; stopping them here keeps oversized input out of the request.
const MAX_PASSWORD_LENGTH = 72;
const WHITESPACE_PATTERN = /\s/g;
const TOTP_CODE_PATTERN = new RegExp(`^\\d{${String(TOTP_CODE_LENGTH)}}$`);

export const loginSchema = z.object({
  email: z
    .string()
    .trim()
    .max(MAX_EMAIL_LENGTH, { error: AUTH_COPY.login.emailInvalid })
    .pipe(z.email({ error: AUTH_COPY.login.emailInvalid })),
  password: z
    .string()
    .min(1, { error: AUTH_COPY.login.passwordRequired })
    .max(MAX_PASSWORD_LENGTH, { error: AUTH_COPY.login.passwordRequired }),
});

/** Authenticator apps show "123 456"; spaces are accepted and removed. */
const codeSchema = z
  .string()
  .transform((enteredCode) => enteredCode.replace(WHITESPACE_PATTERN, ""))
  .pipe(z.string().regex(TOTP_CODE_PATTERN, { error: AUTH_COPY.verify.codeInvalid }));

export const totpCodeSchema = z.object({ code: codeSchema });

export const enrolmentCodeSchema = z.object({
  factorId: z.string().min(1),
  code: codeSchema,
});

export type LoginInput = z.input<typeof loginSchema>;
export type TotpCodeInput = z.input<typeof totpCodeSchema>;
export type EnrolmentCodeInput = z.input<typeof enrolmentCodeSchema>;

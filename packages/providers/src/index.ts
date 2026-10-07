// SMS, email, payment, monitoring and authentication adapters are exported from here (ADR-016).
export type {
  AssuranceLevel,
  AuthCookie,
  AuthCookieOptions,
  AuthCookieStore,
  AuthFailureCode,
  AuthPort,
  AuthResult,
  AuthState,
  PasswordCredentials,
  SignedInState,
  TotpEnrolment,
  TotpVerification,
} from "./auth/auth.port";
export { createSupabaseAuth, type CreateSupabaseAuthOptions } from "./auth/create-supabase-auth";

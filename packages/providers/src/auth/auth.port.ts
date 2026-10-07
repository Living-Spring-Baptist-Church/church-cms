// The authentication port (ADR-016). The dashboard depends on these types only, never on the
// vendor SDK, so the identity provider can change without touching the app.

export type AssuranceLevel = "aal1" | "aal2";

/** Why an authentication call failed. Never carries vendor text a user could see. */
export type AuthFailureCode =
  "invalid_credentials" | "invalid_code" | "rate_limited" | "not_signed_in" | "unavailable";

export type AuthResult<TData> =
  | { readonly ok: true; readonly data: TData }
  | { readonly ok: false; readonly code: AuthFailureCode; readonly detail: string };

export type SignedOutState = { readonly status: "signed_out" };

export type SignedInState = {
  readonly status: "signed_in";
  readonly userId: string;
  readonly email: string;
  readonly currentLevel: AssuranceLevel;
  /** aal2 when the user has a verified two-factor device, so a code is still owed at aal1. */
  readonly nextLevel: AssuranceLevel;
  /** The verified authenticator app of the user, or null when none is enrolled. */
  readonly verifiedFactorId: string | null;
  readonly accessToken: string;
};

export type AuthState = SignedOutState | SignedInState;

export type TotpEnrolment = {
  readonly factorId: string;
  /** An image data URI of the QR code. Never log it. */
  readonly qrCodeDataUri: string;
  /** The shared secret for apps that cannot scan the QR code. Never log it. */
  readonly secret: string;
};

export type PasswordCredentials = {
  readonly email: string;
  readonly password: string;
};

export type TotpVerification = {
  readonly factorId: string;
  readonly code: string;
};

export type AuthPort = {
  signInWithPassword(credentials: PasswordCredentials): Promise<AuthResult<void>>;
  /** Validates the session with the provider (refreshing it when needed) and reports the level. */
  getState(): Promise<AuthState>;
  /** Replaces any unfinished enrolment and starts a new authenticator app enrolment. */
  startTotpEnrolment(): Promise<AuthResult<TotpEnrolment>>;
  /** Ids of this user's authenticator apps that were started but never confirmed. */
  listUnverifiedTotpFactorIds(): Promise<AuthResult<readonly string[]>>;
  /** Challenges and verifies a code. Success raises the session to aal2. */
  verifyTotp(verification: TotpVerification): Promise<AuthResult<void>>;
  signOut(): Promise<AuthResult<void>>;
};

export type AuthCookieOptions = {
  readonly path?: string;
  readonly maxAge?: number;
  readonly domain?: string;
  readonly expires?: Date;
  readonly httpOnly?: boolean;
  readonly secure?: boolean;
  readonly sameSite?: "lax" | "strict" | "none";
};

export type AuthCookie = {
  readonly name: string;
  readonly value: string;
  readonly options: AuthCookieOptions;
};

/** Where the provider keeps the session. The app decides how cookies are read and written. */
export type AuthCookieStore = {
  getAll(): readonly { readonly name: string; readonly value: string }[];
  /** `responseHeaders` must be copied onto the response so session cookies are never cached. */
  setAll(cookies: readonly AuthCookie[], responseHeaders: Readonly<Record<string, string>>): void;
};

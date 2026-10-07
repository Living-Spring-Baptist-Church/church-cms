import type { SupabaseClient, User } from "@supabase/supabase-js";

import type {
  AssuranceLevel,
  AuthFailureCode,
  AuthPort,
  AuthResult,
  AuthState,
  PasswordCredentials,
  TotpEnrolment,
  TotpVerification,
} from "./auth.port";
import {
  mapCodeError,
  mapGeneralError,
  mapSignInError,
  type VendorAuthError,
} from "./supabase-auth.errors";

type VendorAuth = SupabaseClient["auth"];

/** The part of the vendor auth client the adapter uses, so tests can supply a small fake. */
export type SupabaseAuthApi = Pick<
  VendorAuth,
  "signInWithPassword" | "getUser" | "getSession" | "signOut"
> & {
  readonly mfa: Pick<
    VendorAuth["mfa"],
    "enroll" | "listFactors" | "unenroll" | "challengeAndVerify" | "getAuthenticatorAssuranceLevel"
  >;
};

export type SupabaseAuthAdapterOptions = {
  /** Shown to the user inside their authenticator app next to the account email. */
  readonly totpIssuer: string;
};

const TOTP_FACTOR_TYPE = "totp";
const VERIFIED_FACTOR_STATUS = "verified";
const UNVERIFIED_FACTOR_STATUS = "unverified";
const SVG_DATA_URI_PREFIX = "data:image/svg+xml;utf-8,";
const DATA_URI_SCHEME = "data:";

function succeed<TData>(data: TData): AuthResult<TData> {
  return { ok: true, data };
}

function describeFailure(error: VendorAuthError) {
  return `${error.name}${error.code === undefined ? "" : ` (${error.code})`}: ${error.message}`;
}

function fail(
  mapError: (error: VendorAuthError) => AuthFailureCode,
  error: VendorAuthError,
): { ok: false; code: AuthFailureCode; detail: string } {
  return { ok: false, code: mapError(error), detail: describeFailure(error) };
}

function toAssuranceLevel(level: string | null): AssuranceLevel {
  return level === "aal2" ? "aal2" : "aal1";
}

// With several verified apps the newest wins, so the choice never depends on list order.
function findVerifiedTotpFactorId(user: User): string | null {
  const verifiedFactors = (user.factors ?? []).filter(
    (factor) => factor.factor_type === TOTP_FACTOR_TYPE && factor.status === VERIFIED_FACTOR_STATUS,
  );
  const newestFirst = [...verifiedFactors].sort((first, second) =>
    second.created_at.localeCompare(first.created_at),
  );
  return newestFirst[0]?.id ?? null;
}

// Older auth servers return raw SVG markup, newer ones return a ready data URI.
function toQrCodeDataUri(qrCode: string): string {
  return qrCode.startsWith(DATA_URI_SCHEME) ? qrCode : `${SVG_DATA_URI_PREFIX}${qrCode}`;
}

async function readAuthState(auth: SupabaseAuthApi): Promise<AuthState> {
  const { data: userData, error: userError } = await auth.getUser();
  if (userError) {
    return { status: "signed_out" };
  }
  const { data: levelData, error: levelError } = await auth.mfa.getAuthenticatorAssuranceLevel();
  const { data: sessionData } = await auth.getSession();
  if (levelError || !sessionData.session) {
    return { status: "signed_out" };
  }
  return {
    status: "signed_in",
    userId: userData.user.id,
    email: userData.user.email ?? "",
    currentLevel: toAssuranceLevel(levelData.currentLevel),
    nextLevel: toAssuranceLevel(levelData.nextLevel),
    verifiedFactorId: findVerifiedTotpFactorId(userData.user),
    accessToken: sessionData.session.access_token,
  };
}

export function createSupabaseAuthPort(
  auth: SupabaseAuthApi,
  options: SupabaseAuthAdapterOptions,
): AuthPort {
  async function signInWithPassword(credentials: PasswordCredentials): Promise<AuthResult<void>> {
    const { error } = await auth.signInWithPassword(credentials);
    if (error) {
      return fail(mapSignInError, error);
    }
    return succeed(undefined);
  }

  async function listUnverifiedTotpFactorIds(): Promise<AuthResult<readonly string[]>> {
    const { data, error } = await auth.mfa.listFactors();
    if (error) {
      return fail(mapGeneralError, error);
    }
    const unfinishedFactors = data.all.filter(
      (factor) =>
        factor.factor_type === TOTP_FACTOR_TYPE && factor.status === UNVERIFIED_FACTOR_STATUS,
    );
    return succeed(unfinishedFactors.map((factor) => factor.id));
  }

  // Unfinished enrolments pile up when a page is reloaded, and would hit the factor limit.
  async function startTotpEnrolment(): Promise<AuthResult<TotpEnrolment>> {
    const unfinished = await listUnverifiedTotpFactorIds();
    await Promise.all(
      (unfinished.ok ? unfinished.data : []).map((factorId) => auth.mfa.unenroll({ factorId })),
    );
    const { data, error } = await auth.mfa.enroll({
      factorType: TOTP_FACTOR_TYPE,
      issuer: options.totpIssuer,
    });
    if (error) {
      return fail(mapGeneralError, error);
    }
    return succeed({
      factorId: data.id,
      qrCodeDataUri: toQrCodeDataUri(data.totp.qr_code),
      secret: data.totp.secret,
    });
  }

  async function verifyTotp(verification: TotpVerification): Promise<AuthResult<void>> {
    const { error } = await auth.mfa.challengeAndVerify(verification);
    if (error) {
      return fail(mapCodeError, error);
    }
    return succeed(undefined);
  }

  async function signOut(): Promise<AuthResult<void>> {
    const { error } = await auth.signOut({ scope: "local" });
    if (error) {
      return fail(mapGeneralError, error);
    }
    return succeed(undefined);
  }

  return {
    signInWithPassword,
    getState: () => readAuthState(auth),
    startTotpEnrolment,
    listUnverifiedTotpFactorIds,
    verifyTotp,
    signOut,
  };
}

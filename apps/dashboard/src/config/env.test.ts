import { describe, expect, it } from "vitest";

import { readPublicEnv } from "./env";

describe("readPublicEnv", () => {
  it("should return the project url and anon key", () => {
    const env = readPublicEnv({
      NEXT_PUBLIC_SUPABASE_URL: "http://127.0.0.1:54321",
      NEXT_PUBLIC_SUPABASE_ANON_KEY: "anon",
    });
    expect(env).toEqual({ supabaseUrl: "http://127.0.0.1:54321", supabaseAnonKey: "anon" });
  });

  it("should throw naming the missing variable", () => {
    expect(() => readPublicEnv({ NEXT_PUBLIC_SUPABASE_URL: "http://127.0.0.1:54321" })).toThrow(
      "NEXT_PUBLIC_SUPABASE_ANON_KEY",
    );
  });
});

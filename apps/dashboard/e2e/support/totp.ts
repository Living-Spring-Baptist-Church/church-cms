import { createHmac } from "node:crypto";

// RFC 6238 defaults, the same ones Supabase Auth TOTP and authenticator apps use.
const TOTP_PERIOD_SECONDS = 30;
const TOTP_DIGITS = 6;
const MILLISECONDS_PER_SECOND = 1000;
const BASE32_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
const BASE32_BITS_PER_CHARACTER = 5;
const BITS_PER_BYTE = 8;
const BYTE_MASK = 0xff;
const COUNTER_BYTES = 8;
const DYNAMIC_OFFSET_MASK = 0x0f;
const DYNAMIC_CODE_MASK = 0x7fffffff;
const DECIMAL_BASE = 10;

function decodeBase32(secret: string): Buffer {
  const cleaned = secret.replace(/[\s=]/g, "").toUpperCase();
  const bytes: number[] = [];
  let buffer = 0;
  let bitCount = 0;
  for (const character of cleaned) {
    const index = BASE32_ALPHABET.indexOf(character);
    if (index === -1) {
      throw new Error("The setup key is not valid base32");
    }
    buffer = (buffer << BASE32_BITS_PER_CHARACTER) | index;
    bitCount += BASE32_BITS_PER_CHARACTER;
    if (bitCount >= BITS_PER_BYTE) {
      bitCount -= BITS_PER_BYTE;
      bytes.push((buffer >> bitCount) & BYTE_MASK);
    }
  }
  return Buffer.from(bytes);
}

/** The code an authenticator app would show for this setup key at `atMilliseconds`. */
export function generateTotpCode(secret: string, atMilliseconds = Date.now()): string {
  const counter = Math.floor(atMilliseconds / MILLISECONDS_PER_SECOND / TOTP_PERIOD_SECONDS);
  const counterBuffer = Buffer.alloc(COUNTER_BYTES);
  counterBuffer.writeBigUInt64BE(BigInt(counter));
  const digest = createHmac("sha1", decodeBase32(secret)).update(counterBuffer).digest();
  const offset = (digest.at(-1) ?? 0) & DYNAMIC_OFFSET_MASK;
  const binaryCode = digest.readUInt32BE(offset) & DYNAMIC_CODE_MASK;
  return String(binaryCode % DECIMAL_BASE ** TOTP_DIGITS).padStart(TOTP_DIGITS, "0");
}

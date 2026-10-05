const DEFAULT_LOCALE = "en-GH";
// Every currency the church handles (cedi, and any later foreign gift) has 100 minor units.
// Deriving it from Intl left an unreachable fallback branch, so it stays a named constant.
const MINOR_UNITS_PER_MAJOR_UNIT = 100;

/**
 * Formats an integer minor-unit amount (pesewas) for display.
 * Money crosses the wire as `amountMinor`; this is the one place it becomes a string.
 * GraphQL returns BigInt as a string, so callers holding one must convert it to a number first.
 */
export function formatMoney(amountMinor: number, currency: string): string {
  const formatter = new Intl.NumberFormat(DEFAULT_LOCALE, { style: "currency", currency });
  return formatter.format(amountMinor / MINOR_UNITS_PER_MAJOR_UNIT);
}

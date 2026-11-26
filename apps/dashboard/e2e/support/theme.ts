import type { Locator, Page } from "@playwright/test";

// The class packages/config/theme.css uses for its dark tokens, written out so the test does not reuse app code.
export const DARK_THEME_CLASS = "dark";
const TRANSPARENT_BACKGROUND = "rgba(0, 0, 0, 0)";
const RGB_CHANNEL_PATTERN = /rgba?\((\d+),\s*(\d+),\s*(\d+)/;
const RGB_CHANNEL_MAX = 255;
const RGB_CHANNEL_COUNT = 3;
const FIRST_BODY_RECORD_KEY = "lbcE2eDarkAtFirstBody";
// Navy surfaces measure about 0.10 to 0.14 here; white is 1 and light greys sit above 0.8.
export const DARK_SURFACE_MAX_LUMINANCE = 0.25;

/** The colour the user actually sees behind the page: the body, or the root when the body is transparent. */
export async function readPageBackground(page: Page): Promise<string> {
  return page.evaluate((transparentBackground) => {
    const bodyBackground = getComputedStyle(document.body).backgroundColor;
    return bodyBackground === transparentBackground
      ? getComputedStyle(document.documentElement).backgroundColor
      : bodyBackground;
  }, TRANSPARENT_BACKGROUND);
}

export async function hasDarkThemeClass(page: Page): Promise<boolean> {
  return page.evaluate(
    (darkThemeClass) => document.documentElement.classList.contains(darkThemeClass),
    DARK_THEME_CLASS,
  );
}

/** Average channel brightness from 0 (black) to 1 (white). Fails loudly on a colour format it cannot read. */
export async function readBackgroundLuminance(element: Locator): Promise<number> {
  const background = await element.evaluate((node) => getComputedStyle(node).backgroundColor);
  const channels = RGB_CHANNEL_PATTERN.exec(background);
  if (!channels) {
    throw new Error(`Cannot read the background colour "${background}"`);
  }
  const [, red, green, blue] = channels.map(Number);
  return ((red ?? 0) + (green ?? 0) + (blue ?? 0)) / (RGB_CHANNEL_MAX * RGB_CHANNEL_COUNT);
}

/**
 * Records, before any page script runs, whether the dark class was already on <html> when <body>
 * was first inserted. True means a dark device never sees a light first paint.
 */
export async function recordDarkClassAtFirstBody(page: Page): Promise<void> {
  await page.addInitScript(
    ({ darkThemeClass, recordKey }) => {
      const observer = new MutationObserver(() => {
        // The DOM types say body always exists, but it is null while the parser is still in <head>.
        const body = document.body as HTMLElement | null;
        if (body) {
          const isDark = document.documentElement.classList.contains(darkThemeClass);
          sessionStorage.setItem(recordKey, String(isDark));
          observer.disconnect();
        }
      });
      observer.observe(document, { childList: true, subtree: true });
    },
    { darkThemeClass: DARK_THEME_CLASS, recordKey: FIRST_BODY_RECORD_KEY },
  );
}

export async function readDarkClassAtFirstBody(page: Page): Promise<string | null> {
  return page.evaluate((recordKey) => sessionStorage.getItem(recordKey), FIRST_BODY_RECORD_KEY);
}

import { afterEach, describe, expect, it, vi } from "vitest";

import { DARK_COLOR_SCHEME_QUERY, DARK_THEME_CLASS } from "@core/data/theme.data";

import { buildColorSchemeScript } from "./theme.utils";

type ChangeListener = () => void;

type FakeDarkQuery = {
  readonly matches: boolean;
  readonly media: string;
  readonly addEventListener: (eventName: string, listener: ChangeListener) => void;
};

function installFakeDevice(prefersDark: boolean) {
  const device = { prefersDark, listeners: [] as ChangeListener[], queries: [] as string[] };
  const matchMedia = vi.fn((media: string): FakeDarkQuery => {
    device.queries.push(media);
    return {
      get matches() {
        return device.prefersDark;
      },
      media,
      addEventListener: (eventName, listener) => {
        if (eventName === "change") device.listeners.push(listener);
      },
    };
  });
  vi.stubGlobal("matchMedia", matchMedia);
  return {
    device,
    changeSetting: (nextPrefersDark: boolean) => {
      device.prefersDark = nextPrefersDark;
      device.listeners.forEach((listener) => {
        listener();
      });
    },
  };
}

function runColorSchemeScript() {
  // The script is plain browser JavaScript that the layout inlines; run it the way the page does.
  // eslint-disable-next-line @typescript-eslint/no-implied-eval
  const executeScript = new Function(buildColorSchemeScript()) as () => void;
  executeScript();
}

function hasDarkTheme() {
  return document.documentElement.classList.contains(DARK_THEME_CLASS);
}

afterEach(() => {
  vi.unstubAllGlobals();
  document.documentElement.className = "";
});

describe("buildColorSchemeScript", () => {
  it("should apply the dark theme when the device prefers dark", () => {
    const { device } = installFakeDevice(true);

    runColorSchemeScript();

    expect(hasDarkTheme()).toBe(true);
    expect(device.queries).toEqual([DARK_COLOR_SCHEME_QUERY]);
  });

  it("should keep the light theme when the device prefers light", () => {
    installFakeDevice(false);

    runColorSchemeScript();

    expect(hasDarkTheme()).toBe(false);
  });

  it("should keep classes already on the page, such as the font variable", () => {
    document.documentElement.className = "font-variable";
    installFakeDevice(true);

    runColorSchemeScript();

    expect(document.documentElement.classList.contains("font-variable")).toBe(true);
    expect(hasDarkTheme()).toBe(true);
  });

  it("should switch theme when the device setting changes while the page is open", () => {
    const { changeSetting } = installFakeDevice(false);
    runColorSchemeScript();

    changeSetting(true);
    expect(hasDarkTheme()).toBe(true);

    changeSetting(false);
    expect(hasDarkTheme()).toBe(false);
  });

  it("should leave the page light and not throw when the browser cannot read the setting", () => {
    vi.stubGlobal("matchMedia", undefined);

    expect(() => {
      runColorSchemeScript();
    }).not.toThrow();
    expect(hasDarkTheme()).toBe(false);
  });

  it("should be a self-contained statement with no characters that could close the script tag", () => {
    const script = buildColorSchemeScript();

    expect(script).not.toMatch(/<\/script/i);
    expect(script).not.toMatch(/\b(import|require)\b/);
  });
});

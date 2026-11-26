import { DARK_COLOR_SCHEME_QUERY, DARK_THEME_CLASS } from "@core/data/theme.data";

/**
 * Builds the inline script the root layout puts in <head>. It runs before the first paint, so a
 * device set to dark never sees a light flash, and it keeps following the setting while open.
 * It is a string because it must run before React loads; values are JSON encoded so they stay safe.
 */
export function buildColorSchemeScript(): string {
  const themeClass = JSON.stringify(DARK_THEME_CLASS);
  const darkQuery = JSON.stringify(DARK_COLOR_SCHEME_QUERY);
  return [
    "(function () {",
    "  if (typeof window.matchMedia !== 'function') return;",
    `  var darkQuery = window.matchMedia(${darkQuery});`,
    "  var root = document.documentElement;",
    "  function applyColorScheme() {",
    `    root.classList.toggle(${themeClass}, darkQuery.matches);`,
    "  }",
    "  applyColorScheme();",
    "  darkQuery.addEventListener('change', applyColorScheme);",
    "})();",
  ].join("\n");
}

// The one logger of the dashboard (CLAUDE.md section 4). One JSON line per event on stdout or
// stderr, so any log collector can read it. Never pass secrets, tokens or personal data in `context`.

export type LogLevel = "debug" | "info" | "warn" | "error";

export type LogContext = Readonly<Record<string, string | number | boolean | null | undefined>>;

const ERROR_LEVELS: readonly LogLevel[] = ["warn", "error"];

function writeLine(level: LogLevel, message: string, context: LogContext) {
  const line = `${JSON.stringify({ level, message, time: new Date().toISOString(), ...context })}\n`;
  if (ERROR_LEVELS.includes(level)) {
    process.stderr.write(line);
  } else {
    process.stdout.write(line);
  }
}

function createLevelLogger(level: LogLevel) {
  return (message: string, context: LogContext = {}) => {
    writeLine(level, message, context);
  };
}

export const logger = {
  debug: createLevelLogger("debug"),
  info: createLevelLogger("info"),
  warn: createLevelLogger("warn"),
  error: createLevelLogger("error"),
} as const;

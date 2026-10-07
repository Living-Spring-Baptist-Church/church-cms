import { afterEach, describe, expect, it, vi } from "vitest";

import { logger } from "./logger";

afterEach(() => {
  vi.restoreAllMocks();
});

describe("logger", () => {
  it("should write info and debug as one JSON line on stdout", () => {
    const stdout = vi.spyOn(process.stdout, "write").mockReturnValue(true);

    logger.info("Signed in", { requestId: "r1" });
    logger.debug("Details");

    const [firstLine] = stdout.mock.calls[0] as [string];
    expect(JSON.parse(firstLine)).toMatchObject({
      level: "info",
      message: "Signed in",
      requestId: "r1",
    });
    expect(stdout).toHaveBeenCalledTimes(2);
  });

  it("should write warnings and errors on stderr", () => {
    const stderr = vi.spyOn(process.stderr, "write").mockReturnValue(true);

    logger.warn("Careful");
    logger.error("Broken", { code: "server" });

    expect(stderr).toHaveBeenCalledTimes(2);
    const [secondLine] = stderr.mock.calls[1] as [string];
    expect(JSON.parse(secondLine)).toMatchObject({ level: "error", code: "server" });
  });
});

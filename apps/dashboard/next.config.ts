import { createSecurityHeaderRoutes } from "@lbc/config/security-headers";
import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  transpilePackages: ["@lbc/ui"],
  poweredByHeader: false,
  headers: () => createSecurityHeaderRoutes(),
};

export default nextConfig;

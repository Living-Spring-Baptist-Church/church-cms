import { prepareLocalDemoStaff } from "./support/local-supabase";

export default function globalSetup(): void {
  prepareLocalDemoStaff();
}

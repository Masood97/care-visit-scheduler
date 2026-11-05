import { defineConfig, devices } from "@playwright/test";

// End-to-end tests of the main flows against a running app and the local Supabase stack
// with the seed (`npx supabase db reset`). The tests share one database, so they run
// one at a time, in file order.
export default defineConfig({
  testDir: "./e2e",
  fullyParallel: false,
  workers: 1,
  retries: process.env.CI ? 1 : 0,
  timeout: 45_000,
  expect: { timeout: 10_000 },
  reporter: process.env.CI ? [["github"], ["html", { open: "never" }]] : "list",
  use: {
    baseURL: process.env.E2E_BASE_URL ?? "http://localhost:3000",
    trace: "retain-on-failure",
    timezoneId: "Australia/Sydney",
  },
  projects: [
    { name: "desktop", use: { ...devices["Desktop Chrome"] }, testIgnore: /worker\.spec\.ts/ },
    // Workers use a phone: run their flow at phone size.
    { name: "phone", use: { ...devices["Pixel 7"] }, testMatch: /worker\.spec\.ts/ },
  ],
  // CI builds the app first; locally an already-running `npm run dev` is reused.
  webServer: {
    command: "npm run start",
    url: "http://localhost:3000/login",
    reuseExistingServer: !process.env.CI,
    timeout: 120_000,
  },
});

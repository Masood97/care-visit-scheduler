import { expect, type Page } from "@playwright/test";

export const PASSWORD = "Password123!"; // seeded local/CI users only (supabase/seed.sql)
export const SYDNEY = "Australia/Sydney";

export async function signIn(page: Page, email: string) {
  await page.goto("/login");
  await page.getByLabel("Email").fill(email);
  await page.getByLabel("Password").fill(PASSWORD);
  await page.getByRole("button", { name: "Sign in" }).click();
  await expect(page).not.toHaveURL(/\/login/);
}

/** A time `minutesFromNow` ahead, as a datetime-local value and an "HH:MM" label in the zone. */
export function zoned(minutesFromNow: number, timeZone = SYDNEY) {
  const date = new Date(Date.now() + minutesFromNow * 60_000);
  const p = Object.fromEntries(
    new Intl.DateTimeFormat("en-CA", {
      timeZone,
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
      hourCycle: "h23",
    })
      .formatToParts(date)
      .map((x) => [x.type, x.value]),
  );
  return { input: `${p.year}-${p.month}-${p.day}T${p.hour}:${p.minute}`, label: `${p.hour}:${p.minute}` };
}

/** Picks an option in one of the shadcn (Radix) selects by its label. */
export async function choose(page: Page, label: string | RegExp, option: string) {
  // Exact match for plain labels, so "Worker" doesn't also match "Second worker …".
  await page.getByRole("combobox", { name: label, exact: typeof label === "string" }).click();
  await page.getByRole("option", { name: option, exact: true }).click();
}

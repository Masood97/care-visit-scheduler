import { expect, test } from "@playwright/test";

import { signIn } from "./helpers";

// Runs at phone size (see playwright.config.ts). Margaret Ellis's home in the seed is
// client 1 of Harbour Home Care: -33.8650 + 0.009, 151.2094 + 0.006.
const HOME = { latitude: -33.856, longitude: 151.2154 };
const FAR_AWAY = { latitude: -33.8608, longitude: 151.2154 }; // ~530 m south

test.use({ permissions: ["geolocation"], geolocation: FAR_AWAY });

test("a worker checks in from the client's home (not from 500 m away) and checks out", async ({ page, context }) => {
  // The visit the coordinator test booked for Sofia Alvarez, starting in ~10 minutes.
  const card = page.locator('[data-slot="card"]').filter({ hasText: "E2E check-in visit" });

  await signIn(page, "worker2@harbour.example"); // Sofia Alvarez
  await expect(page).toHaveURL(/\/my-visits/);
  await expect(card).toContainText("Margaret Ellis");
  await expect(card).toContainText("Scheduled");

  // Too far away: refused, with the distance in plain words (never a raw database error).
  await card.getByRole("button", { name: "Check in" }).click();
  await expect(page.getByText(/You're about \d+ m from the client's home/)).toBeVisible();
  await expect(card).toContainText("Scheduled");

  // At the door: checked in, the visit is in progress.
  await context.setGeolocation(HOME);
  await card.getByRole("button", { name: "Check in" }).click();
  await expect(page.getByText("Checked in. Have a good visit.")).toBeVisible();
  await expect(card).toContainText("In progress");

  // Check out: the only worker on the visit, so it is completed.
  await card.getByRole("button", { name: "Check out" }).click();
  await expect(page.getByText("Checked out. Visit completed.")).toBeVisible();
  await expect(card).toContainText("Completed");
});

test("a worker sees the 2:1 visit they share, with their colleague's name", async ({ page }) => {
  await signIn(page, "worker1@harbour.example"); // Wei Chen
  const shared = page.locator('[data-slot="card"]').filter({ hasText: "E2E safe lift" });
  await expect(shared).toContainText("2:1 visit with Sofia Alvarez");
});

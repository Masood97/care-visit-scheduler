import { expect, test } from "@playwright/test";

import { choose, signIn, zoned } from "./helpers";

// Coordinator of Harbour Home Care (Australia/Sydney) from the seed.
test.describe("coordinator", () => {
  test("signed-out visitors are sent to the login page", async ({ page }) => {
    await page.goto("/visits");
    await expect(page).toHaveURL(/\/login/);
  });

  test("books a 2:1 visit and a 1:1 visit, then sees a clear double-booking message", async ({ page }) => {
    await signIn(page, "coordinator@harbour.example");
    await expect(page).toHaveURL(/\/visits/);
    const dialog = page.getByRole("dialog", { name: "Book a visit" });

    // 2:1 visit in a slot both seeded workers have free (3 days ahead, 12:00-13:00 Sydney).
    const day3 = zoned(3 * 24 * 60).input.slice(0, 10);
    await page.getByRole("button", { name: "Book visit" }).click();
    await choose(page, "Client", "Desmond Hale");
    await choose(page, "Worker", "Sofia Alvarez");
    await choose(page, /Second worker/, "Wei Chen");
    await dialog.getByLabel("Starts").fill(`${day3}T12:00`);
    await dialog.getByLabel("Ends").fill(`${day3}T13:00`);
    await dialog.getByLabel("Notes").fill("E2E safe lift");
    await dialog.getByRole("button", { name: "Book visit" }).click();
    await expect(page.getByText("Visit booked.")).toBeVisible();

    // 1:1 visit starting in 10 minutes (open for check-in), used by the worker test.
    await page.getByRole("button", { name: "Book visit" }).click();
    await choose(page, "Client", "Margaret Ellis");
    await choose(page, "Worker", "Sofia Alvarez");
    await dialog.getByLabel("Starts").fill(zoned(10).input);
    await dialog.getByLabel("Ends").fill(zoned(70).input);
    await dialog.getByLabel("Notes").fill("E2E check-in visit");
    await dialog.getByRole("button", { name: "Book visit" }).click();
    await expect(page.getByText("Visit booked.").last()).toBeVisible();

    // Same worker, overlapping time: the database refuses, the UI explains.
    await page.getByRole("button", { name: "Book visit" }).click();
    await choose(page, "Client", "Tomasz Nowak");
    await choose(page, "Worker", "Sofia Alvarez");
    await dialog.getByLabel("Starts").fill(zoned(20).input);
    await dialog.getByLabel("Ends").fill(zoned(50).input);
    await dialog.getByRole("button", { name: "Book visit" }).click();
    await expect(dialog.getByRole("alert")).toContainText("already has another visit at that time");
    await expect(dialog.getByRole("alert")).not.toContainText("exclusion"); // never the raw database error
  });

  test("cancels a scheduled visit through the confirm dialog", async ({ page }) => {
    await signIn(page, "coordinator@harbour.example");
    const dialog = page.getByRole("dialog", { name: "Book a visit" });

    // Its own visit, so the test never touches visits other tests rely on.
    const day3 = zoned(3 * 24 * 60).input.slice(0, 10);
    await page.getByRole("button", { name: "Book visit" }).click();
    await choose(page, "Client", "Aiyana Brooks");
    await choose(page, "Worker", "Sofia Alvarez");
    await dialog.getByLabel("Starts").fill(`${day3}T15:00`);
    await dialog.getByLabel("Ends").fill(`${day3}T16:00`);
    await dialog.getByLabel("Notes").fill("E2E to cancel");
    await dialog.getByRole("button", { name: "Book visit" }).click();
    await expect(page.getByText("Visit booked.")).toBeVisible();

    await page.goto(`/visits?week=${day3}`); // the page snaps to that date's Monday
    const row = page.getByRole("row", { name: /E2E to cancel/ });
    await row.getByRole("button", { name: "Cancel", exact: true }).click();
    const confirm = page.getByRole("alertdialog", { name: "Cancel this visit?" });
    await expect(confirm).toContainText("Aiyana Brooks");
    await confirm.getByRole("button", { name: "Cancel visit" }).click();
    await expect(page.getByText("Visit cancelled.")).toBeVisible();
    await expect(row).toContainText("Cancelled");
    await expect(row.getByRole("button", { name: "Cancel", exact: true })).toHaveCount(0);
  });

  test("archives and restores a client", async ({ page }) => {
    await signIn(page, "coordinator@harbour.example");
    await page.goto("/clients");
    const row = page.getByRole("row", { name: /Priya Raman/ });

    await row.getByRole("button", { name: "Archive" }).click();
    await expect(page.getByText("Client archived.")).toBeVisible();
    await expect(row.getByText("Archived")).toBeVisible();

    await row.getByRole("button", { name: "Restore" }).click();
    await expect(page.getByText("Client restored.")).toBeVisible();
    await expect(row.getByText("Active")).toBeVisible();
  });
});

test.describe("owner", () => {
  test("sees the weekly hours report", async ({ page }) => {
    await signIn(page, "owner@harbour.example");
    await expect(page).toHaveURL(/\/hours/);
    await expect(page.getByRole("heading", { name: "Weekly hours" })).toBeVisible();
    await expect(page.getByRole("cell", { name: "Wei Chen" }).first()).toBeVisible();
    await expect(page.getByRole("cell", { name: "Total" })).toBeVisible();
  });
});

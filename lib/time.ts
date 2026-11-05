// Date helpers that work in an organization's IANA time zone, independent of the
// browser's or server's zone. Writes send local wall-clock time plus the zone name
// (e.g. "2026-11-06 09:00 Australia/Sydney"); Postgres converts that to timestamptz,
// handling daylight saving correctly.

/** "2026-11-06T09:00" (datetime-local value) + zone -> Postgres timestamptz literal. */
export function toZonedTimestamp(localDateTime: string, timeZone: string): string {
  return `${localDateTime.replace("T", " ")} ${timeZone}`;
}

function parts(date: Date, timeZone: string) {
  const formatted = new Intl.DateTimeFormat("en-CA", {
    timeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    hourCycle: "h23",
  }).formatToParts(date);
  const get = (type: string) => formatted.find((p) => p.type === type)?.value ?? "";
  return { year: get("year"), month: get("month"), day: get("day"), hour: get("hour"), minute: get("minute") };
}

/** Instant -> "2026-11-06T09:00" in the zone, for a datetime-local input. */
export function toLocalInputValue(iso: string, timeZone: string): string {
  const p = parts(new Date(iso), timeZone);
  return `${p.year}-${p.month}-${p.day}T${p.hour}:${p.minute}`;
}

/** Today's date ("YYYY-MM-DD") in the zone. */
export function todayIn(timeZone: string): string {
  const p = parts(new Date(), timeZone);
  return `${p.year}-${p.month}-${p.day}`;
}

/** Plain calendar arithmetic on "YYYY-MM-DD" strings (no time zone involved). */
export function addDays(date: string, days: number): string {
  const d = new Date(`${date}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + days);
  return d.toISOString().slice(0, 10);
}

/** Monday of the week containing the date (ISO weeks, as in the hours report). */
export function mondayOf(date: string): string {
  const day = new Date(`${date}T00:00:00Z`).getUTCDay(); // 0 = Sunday
  return addDays(date, day === 0 ? -6 : 1 - day);
}

export function isDateString(value: unknown): value is string {
  return typeof value === "string" && /^\d{4}-\d{2}-\d{2}$/.test(value) && !Number.isNaN(Date.parse(value));
}

export function formatDateTime(iso: string, timeZone: string): string {
  return new Intl.DateTimeFormat("en-GB", {
    timeZone,
    weekday: "short",
    day: "numeric",
    month: "short",
    hour: "2-digit",
    minute: "2-digit",
  }).format(new Date(iso));
}

export function formatTime(iso: string, timeZone: string): string {
  return new Intl.DateTimeFormat("en-GB", { timeZone, hour: "2-digit", minute: "2-digit" }).format(new Date(iso));
}

export function formatDay(date: string): string {
  return new Intl.DateTimeFormat("en-GB", { timeZone: "UTC", weekday: "short", day: "numeric", month: "short" }).format(
    new Date(`${date}T00:00:00Z`),
  );
}

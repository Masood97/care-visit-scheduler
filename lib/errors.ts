// Turns database errors into messages a user can act on. The raw Postgres message is
// never shown: every known rule has its own sentence, everything else gets a generic one.
// Codes are documented in docs/schema.md.

type DbError = { code?: string; message?: string } | null | undefined;

const BY_CODE: Record<string, string> = {
  "23P01": "This worker already has a visit at that time. Pick another time or worker.",
  CV001: "This client is archived, so they can't get new visits.",
  CV002: "Visits can only be assigned to workers.",
  CV003: "That status change isn't allowed for this visit.",
  CV004: "New visits always start as scheduled.",
  CV005: "Only scheduled visits can be rescheduled or reassigned.",
  CV006: "A visit starts when the worker checks in.",
  CV007: "A visit completes when the worker checks out.",
  CV010: "This visit isn't assigned to you.",
  CV011: "This visit is not open for check-in any more.",
  CV012: "Check-in opens 30 minutes before the visit starts.",
  CV013: "Check-in closed at the scheduled end of the visit.",
  CV015: "Your location couldn't be read. Allow location access and try again.",
  CV020: "Only the worker who checked in can check out.",
  CV021: "This visit isn't in progress.",
  CV030: "The audit log can't be changed.",
  CV040: "This worker still has open visits. Reassign or cancel them first.",
  CV041: "An organization needs at least one owner.",
  CV043: "Records can't be moved to another organization.",
  "42501": "You don't have permission to do that.",
};

// CHECK / foreign-key violations: Postgres names the constraint in the message.
const BY_CONSTRAINT: Record<string, string> = {
  visits_ends_after_start: "The visit must end after it starts.",
  visits_max_12_hours: "A visit can last at most 12 hours.",
  visits_client_fk: "This client has visits, so it can't be deleted. Archive it instead.",
  clients_latitude_range: "Latitude must be between -90 and 90.",
  clients_longitude_range: "Longitude must be between -180 and 180.",
};

export function friendlyError(error: DbError): string {
  if (!error) return "Something went wrong. Please try again.";

  if (error.code === "CV014") {
    // The function reports the distance; show it in our own words.
    const metres = error.message?.match(/(\d+) m/)?.[1];
    return metres
      ? `You're about ${metres} m from the client's home. Check-in works within 200 m.`
      : "You're too far from the client's home. Check-in works within 200 m.";
  }

  if (error.code && BY_CODE[error.code]) return BY_CODE[error.code];

  const constraint = Object.keys(BY_CONSTRAINT).find((name) => error.message?.includes(name));
  if (constraint) return BY_CONSTRAINT[constraint];

  return "Something went wrong. Please try again.";
}

export type ActionResult = { ok: true; message?: string } | { ok: false; error: string };

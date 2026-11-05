import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { requireRole } from "@/lib/session";
import { addDays, formatDay, formatTime, todayIn, toLocalInputValue, toZonedTimestamp } from "@/lib/time";

import { StatusBadge } from "../status-badge";
import { CheckButton } from "./check-button";

// Phone-first list of the visits the signed-in worker is assigned to (alone or as one of
// two workers): yesterday to a week ahead. Each worker checks in and out separately.
export default async function MyVisitsPage() {
  const { supabase, user, active } = await requireRole(["worker"]);
  const tz = active.timeZone;
  const today = todayIn(tz);

  // RLS returns exactly the visits this worker is assigned to, and their own events.
  const [visitsRes, eventsRes] = await Promise.all([
    supabase
      .from("visits")
      .select(
        "id, starts_at, ends_at, status, notes, client:clients(full_name, address), visit_workers(worker_id, member:organization_members!visit_workers_worker_fk(full_name))",
      )
      .eq("organization_id", active.organizationId)
      .gte("starts_at", toZonedTimestamp(`${addDays(today, -1)}T00:00`, tz))
      .lt("starts_at", toZonedTimestamp(`${addDays(today, 8)}T00:00`, tz))
      .order("starts_at"),
    supabase
      .from("visit_events")
      .select("visit_id, event_type")
      .eq("organization_id", active.organizationId)
      .eq("worker_id", user.id),
  ]);

  if (visitsRes.error || eventsRes.error) {
    return <p className="text-destructive">Your visits couldn&apos;t be loaded. Refresh the page to try again.</p>;
  }

  const mine = new Set(eventsRes.data.map((e) => `${e.visit_id}:${e.event_type}`));

  return (
    <div className="mx-auto grid max-w-md gap-4">
      <div>
        <h1 className="text-2xl font-semibold">My visits</h1>
        <p className="text-sm text-muted-foreground">
          Check in from the client&apos;s home: within 200 m, from 30 minutes before the start.
        </p>
      </div>

      {visitsRes.data.length === 0 && (
        <p className="rounded-md border border-dashed p-8 text-center text-muted-foreground">No visits this week.</p>
      )}

      {visitsRes.data.map((v) => {
        const checkedIn = mine.has(`${v.id}:check_in`);
        const checkedOut = mine.has(`${v.id}:check_out`);
        const colleagues = v.visit_workers
          .filter((w) => w.worker_id !== user.id)
          .map((w) => w.member?.full_name)
          .filter(Boolean);

        return (
          <Card key={v.id}>
            <CardHeader>
              <div className="flex items-start justify-between gap-2">
                <div>
                  <CardTitle>{v.client?.full_name}</CardTitle>
                  <CardDescription>{v.client?.address}</CardDescription>
                </div>
                <StatusBadge status={v.status} />
              </div>
            </CardHeader>
            <CardContent className="grid gap-3">
              <p className="text-sm">
                {formatDay(toLocalInputValue(v.starts_at, tz).slice(0, 10))}, {formatTime(v.starts_at, tz)}–
                {formatTime(v.ends_at, tz)}
              </p>
              {colleagues.length > 0 && <p className="text-sm">2:1 visit with {colleagues.join(", ")}</p>}
              {v.notes && <p className="text-sm text-muted-foreground">{v.notes}</p>}
              {!checkedIn && (v.status === "scheduled" || v.status === "in_progress") && (
                <CheckButton visitId={v.id} kind="in" />
              )}
              {checkedIn && !checkedOut && v.status === "in_progress" && <CheckButton visitId={v.id} kind="out" />}
              {checkedOut && v.status === "in_progress" && (
                <p className="text-sm text-muted-foreground">You&apos;ve checked out. Waiting for your colleague to check out.</p>
              )}
            </CardContent>
          </Card>
        );
      })}
    </div>
  );
}

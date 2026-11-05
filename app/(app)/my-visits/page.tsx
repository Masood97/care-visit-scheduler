import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { requireRole } from "@/lib/session";
import { addDays, formatDay, formatTime, todayIn, toLocalInputValue, toZonedTimestamp } from "@/lib/time";

import { StatusBadge } from "../status-badge";
import { CheckButton } from "./check-button";

// Phone-first list of the signed-in worker's visits: yesterday to a week ahead.
export default async function MyVisitsPage() {
  const { supabase, user, active } = await requireRole(["worker"]);
  const tz = active.timeZone;
  const today = todayIn(tz);

  // RLS already limits a worker to their own visits; the worker_id filter just makes the intent explicit.
  const { data: visits, error } = await supabase
    .from("visits")
    .select("id, starts_at, ends_at, status, notes, client:clients(full_name, address)")
    .eq("organization_id", active.organizationId)
    .eq("worker_id", user.id)
    .gte("starts_at", toZonedTimestamp(`${addDays(today, -1)}T00:00`, tz))
    .lt("starts_at", toZonedTimestamp(`${addDays(today, 8)}T00:00`, tz))
    .order("starts_at");

  if (error) {
    return <p className="text-destructive">Your visits couldn&apos;t be loaded. Refresh the page to try again.</p>;
  }

  return (
    <div className="mx-auto grid max-w-md gap-4">
      <div>
        <h1 className="text-2xl font-semibold">My visits</h1>
        <p className="text-sm text-muted-foreground">
          Check in from the client&apos;s home: within 200 m, from 30 minutes before the start.
        </p>
      </div>

      {visits.length === 0 && (
        <p className="rounded-md border border-dashed p-8 text-center text-muted-foreground">No visits this week.</p>
      )}

      {visits.map((v) => (
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
            {v.notes && <p className="text-sm text-muted-foreground">{v.notes}</p>}
            {v.status === "scheduled" && <CheckButton visitId={v.id} kind="in" />}
            {v.status === "in_progress" && <CheckButton visitId={v.id} kind="out" />}
          </CardContent>
        </Card>
      ))}
    </div>
  );
}

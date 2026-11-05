import { Table, TableBody, TableCell, TableFooter, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { getSession } from "@/lib/session";
import { addDays, formatDay, mondayOf, todayIn } from "@/lib/time";

// Weekly hours report. The worker_weekly_hours view follows RLS: owners and coordinators
// see their whole organization, workers see only their own rows.
export default async function HoursPage() {
  const { supabase, active } = await getSession();
  if (!active) return null;

  const since = addDays(mondayOf(todayIn(active.timeZone)), -7 * 7); // this week + the 7 before it

  const { data: rows, error } = await supabase
    .from("worker_weekly_hours")
    .select("worker_id, worker_name, week_start, visits_completed, hours")
    .eq("organization_id", active.organizationId)
    .gte("week_start", since)
    .order("week_start", { ascending: false })
    .order("worker_name");

  if (error) {
    return <p className="text-destructive">The hours report couldn&apos;t be loaded. Refresh the page to try again.</p>;
  }

  const total = rows.reduce((sum, r) => sum + Number(r.hours ?? 0), 0);
  const isWorker = active.role === "worker";

  return (
    <div className="grid gap-6">
      <div>
        <h1 className="text-2xl font-semibold">{isWorker ? "My hours" : "Weekly hours"}</h1>
        <p className="text-sm text-muted-foreground">
          Completed hours (check-in to check-out) per week for the last 8 weeks. Weeks start on Monday in{" "}
          {active.timeZone}.
        </p>
      </div>

      {rows.length === 0 ? (
        <p className="rounded-md border border-dashed p-8 text-center text-muted-foreground">
          No completed visits in the last 8 weeks.
        </p>
      ) : (
        <div className="overflow-x-auto rounded-md border">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Week of</TableHead>
                <TableHead>Worker</TableHead>
                <TableHead className="text-right">Visits</TableHead>
                <TableHead className="text-right">Hours</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {rows.map((r) => (
                <TableRow key={`${r.week_start}-${r.worker_id}`}>
                  <TableCell>{r.week_start ? formatDay(r.week_start) : ""}</TableCell>
                  <TableCell>{r.worker_name}</TableCell>
                  <TableCell className="text-right tabular-nums">{r.visits_completed}</TableCell>
                  <TableCell className="text-right tabular-nums">{Number(r.hours ?? 0).toFixed(2)}</TableCell>
                </TableRow>
              ))}
            </TableBody>
            <TableFooter>
              <TableRow>
                <TableCell colSpan={3}>Total</TableCell>
                <TableCell className="text-right tabular-nums">{total.toFixed(2)}</TableCell>
              </TableRow>
            </TableFooter>
          </Table>
        </div>
      )}
    </div>
  );
}

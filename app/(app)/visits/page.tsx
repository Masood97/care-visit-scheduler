import Link from "next/link";

import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { requireRole } from "@/lib/session";
import { addDays, formatDay, formatTime, isDateString, mondayOf, todayIn, toLocalInputValue, toZonedTimestamp } from "@/lib/time";

import { CancelVisitButton } from "./cancel-button";
import { VisitFormDialog } from "./visit-form";
import { StatusBadge } from "../status-badge";

export default async function VisitsPage({ searchParams }: PageProps<"/visits">) {
  const { supabase, active } = await requireRole(["owner", "coordinator"]);
  const tz = active.timeZone;

  const requested = (await searchParams).week;
  const weekStart = mondayOf(isDateString(requested) ? requested : todayIn(tz));
  const weekEnd = addDays(weekStart, 7);

  // The week runs Monday 00:00 to Monday 00:00 in the agency's time zone.
  const [visitsRes, clientsRes, workersRes] = await Promise.all([
    supabase
      .from("visits")
      .select(
        "id, client_id, worker_id, starts_at, ends_at, status, notes, client:clients(full_name, address), worker:organization_members!visits_worker_fk(full_name)",
      )
      .eq("organization_id", active.organizationId)
      .gte("starts_at", toZonedTimestamp(`${weekStart}T00:00`, tz))
      .lt("starts_at", toZonedTimestamp(`${weekEnd}T00:00`, tz))
      .order("starts_at"),
    supabase
      .from("clients")
      .select("id, full_name")
      .eq("organization_id", active.organizationId)
      .eq("status", "active")
      .order("full_name"),
    supabase
      .from("organization_members")
      .select("user_id, full_name")
      .eq("organization_id", active.organizationId)
      .eq("role", "worker")
      .order("full_name"),
  ]);

  if (visitsRes.error || clientsRes.error || workersRes.error) {
    return <p className="text-destructive">Visits couldn&apos;t be loaded. Refresh the page to try again.</p>;
  }

  const clients = clientsRes.data.map((c) => ({ id: c.id, name: c.full_name }));
  const workers = workersRes.data.map((w) => ({ id: w.user_id, name: w.full_name }));
  const visits = visitsRes.data;

  return (
    <div className="grid gap-6">
      <div className="flex flex-wrap items-center gap-3">
        <div>
          <h1 className="text-2xl font-semibold">Visits</h1>
          <p className="text-sm text-muted-foreground">
            Week of {formatDay(weekStart)} · {active.organizationName} ({tz})
          </p>
        </div>
        <div className="ml-auto flex flex-wrap gap-2">
          <Button asChild variant="outline" size="sm">
            <Link href={`/visits?week=${addDays(weekStart, -7)}`}>← Previous</Link>
          </Button>
          <Button asChild variant="outline" size="sm">
            <Link href="/visits">This week</Link>
          </Button>
          <Button asChild variant="outline" size="sm">
            <Link href={`/visits?week=${weekEnd}`}>Next →</Link>
          </Button>
          <VisitFormDialog clients={clients} workers={workers} timeZone={tz} trigger={<Button size="sm">Book visit</Button>} />
        </div>
      </div>

      {visits.length === 0 ? (
        <p className="rounded-md border border-dashed p-8 text-center text-muted-foreground">
          No visits this week. Use “Book visit” to add one.
        </p>
      ) : (
        <div className="overflow-x-auto rounded-md border">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>When</TableHead>
                <TableHead>Client</TableHead>
                <TableHead>Worker</TableHead>
                <TableHead>Status</TableHead>
                <TableHead>Notes</TableHead>
                <TableHead className="text-right">Actions</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {visits.map((v) => (
                <TableRow key={v.id}>
                  <TableCell className="whitespace-nowrap">
                    {formatDay(toLocalInputValue(v.starts_at, tz).slice(0, 10))} {formatTime(v.starts_at, tz)}–
                    {formatTime(v.ends_at, tz)}
                  </TableCell>
                  <TableCell>{v.client?.full_name}</TableCell>
                  <TableCell>{v.worker?.full_name}</TableCell>
                  <TableCell>
                    <StatusBadge status={v.status} />
                  </TableCell>
                  <TableCell className="max-w-56 truncate text-muted-foreground">{v.notes}</TableCell>
                  <TableCell className="text-right whitespace-nowrap">
                    {v.status === "scheduled" ? (
                      <>
                        <VisitFormDialog
                          clients={clients}
                          workers={workers}
                          timeZone={tz}
                          visitId={v.id}
                          defaultValues={{
                            clientId: v.client_id,
                            workerId: v.worker_id,
                            startsAt: toLocalInputValue(v.starts_at, tz),
                            endsAt: toLocalInputValue(v.ends_at, tz),
                            notes: v.notes ?? "",
                          }}
                          trigger={
                            <Button variant="ghost" size="sm">
                              Edit
                            </Button>
                          }
                        />
                        <CancelVisitButton visitId={v.id} />
                      </>
                    ) : (
                      <Badge variant="outline">Locked</Badge>
                    )}
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </div>
      )}
    </div>
  );
}

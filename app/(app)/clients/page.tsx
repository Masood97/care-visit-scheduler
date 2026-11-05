import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { requireRole } from "@/lib/session";

import { ArchiveClientButton } from "./archive-button";
import { ClientFormDialog } from "./client-form";

export default async function ClientsPage() {
  const { supabase, active } = await requireRole(["owner", "coordinator"]);

  const { data: clients, error } = await supabase
    .from("clients")
    .select("id, full_name, address, latitude, longitude, status")
    .eq("organization_id", active.organizationId)
    .order("status")
    .order("full_name");

  if (error) {
    return <p className="text-destructive">Clients couldn&apos;t be loaded. Refresh the page to try again.</p>;
  }

  return (
    <div className="grid gap-6">
      <div className="flex flex-wrap items-center gap-3">
        <div>
          <h1 className="text-2xl font-semibold">Clients</h1>
          <p className="text-sm text-muted-foreground">
            Archived clients keep their history but can&apos;t get new visits.
          </p>
        </div>
        <div className="ml-auto">
          <ClientFormDialog trigger={<Button size="sm">Add client</Button>} />
        </div>
      </div>

      <div className="overflow-x-auto rounded-md border">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Name</TableHead>
              <TableHead>Address</TableHead>
              <TableHead>Location</TableHead>
              <TableHead>Status</TableHead>
              <TableHead className="text-right">Actions</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {clients.map((c) => (
              <TableRow key={c.id}>
                <TableCell className="font-medium">{c.full_name}</TableCell>
                <TableCell>{c.address}</TableCell>
                <TableCell className="text-muted-foreground tabular-nums">
                  {c.latitude.toFixed(4)}, {c.longitude.toFixed(4)}
                </TableCell>
                <TableCell>
                  <Badge variant={c.status === "active" ? "secondary" : "outline"}>
                    {c.status === "active" ? "Active" : "Archived"}
                  </Badge>
                </TableCell>
                <TableCell className="text-right whitespace-nowrap">
                  <ClientFormDialog
                    clientId={c.id}
                    defaultValues={{
                      fullName: c.full_name,
                      address: c.address,
                      latitude: String(c.latitude),
                      longitude: String(c.longitude),
                    }}
                    trigger={
                      <Button variant="ghost" size="sm">
                        Edit
                      </Button>
                    }
                  />
                  <ArchiveClientButton clientId={c.id} archived={c.status === "archived"} />
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </div>
    </div>
  );
}

import { Badge } from "@/components/ui/badge";
import type { Database } from "@/lib/database.types";

type Status = Database["public"]["Enums"]["visit_status"];

const LABEL: Record<Status, string> = {
  scheduled: "Scheduled",
  in_progress: "In progress",
  completed: "Completed",
  cancelled: "Cancelled",
};

const VARIANT: Record<Status, "default" | "secondary" | "outline" | "destructive"> = {
  scheduled: "outline",
  in_progress: "default",
  completed: "secondary",
  cancelled: "destructive",
};

export function StatusBadge({ status }: { status: Status }) {
  return <Badge variant={VARIANT[status]}>{LABEL[status]}</Badge>;
}

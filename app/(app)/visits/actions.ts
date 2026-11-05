"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";

import { friendlyError, type ActionResult } from "@/lib/errors";
import { visitSchema, type VisitInput } from "@/lib/schemas";
import { requireRole } from "@/lib/session";
import { toZonedTimestamp } from "@/lib/time";

// Owners and coordinators book visits. The database enforces the same rule (RLS),
// plus no double booking, valid times, archived clients and the status flow.
const STAFF = ["owner", "coordinator"] as const;

function toRow(input: VisitInput, timeZone: string) {
  return {
    client_id: input.clientId,
    worker_id: input.workerId,
    // Local wall-clock time in the agency's zone; Postgres converts it to an instant.
    starts_at: toZonedTimestamp(input.startsAt, timeZone),
    ends_at: toZonedTimestamp(input.endsAt, timeZone),
    notes: input.notes || null,
  };
}

export async function createVisit(input: VisitInput): Promise<ActionResult> {
  const parsed = visitSchema.safeParse(input);
  if (!parsed.success) return { ok: false, error: parsed.error.issues[0]?.message ?? "Check the form." };

  const { supabase, active } = await requireRole([...STAFF]);
  const { error } = await supabase
    .from("visits")
    .insert({ organization_id: active.organizationId, ...toRow(parsed.data, active.timeZone) });
  if (error) return { ok: false, error: friendlyError(error) };

  revalidatePath("/visits");
  return { ok: true, message: "Visit booked." };
}

export async function updateVisit(visitId: string, input: VisitInput): Promise<ActionResult> {
  const parsed = visitSchema.safeParse(input);
  if (!parsed.success || !z.uuid().safeParse(visitId).success) return { ok: false, error: "Check the form." };

  const { supabase, active } = await requireRole([...STAFF]);
  const { data, error } = await supabase
    .from("visits")
    .update(toRow(parsed.data, active.timeZone))
    .eq("id", visitId)
    .select("id");
  if (error) return { ok: false, error: friendlyError(error) };
  if (!data?.length) return { ok: false, error: "That visit no longer exists or you can't edit it." };

  revalidatePath("/visits");
  return { ok: true, message: "Visit updated." };
}

export async function cancelVisit(visitId: string): Promise<ActionResult> {
  if (!z.uuid().safeParse(visitId).success) return { ok: false, error: "Unknown visit." };

  const { supabase } = await requireRole([...STAFF]);
  const { data, error } = await supabase.from("visits").update({ status: "cancelled" }).eq("id", visitId).select("id");
  if (error) return { ok: false, error: friendlyError(error) };
  if (!data?.length) return { ok: false, error: "That visit no longer exists or you can't cancel it." };

  revalidatePath("/visits");
  return { ok: true, message: "Visit cancelled." };
}

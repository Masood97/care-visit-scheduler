"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";

import { friendlyError, type ActionResult } from "@/lib/errors";
import { visitSchema, type VisitInput } from "@/lib/schemas";
import { requireRole } from "@/lib/session";
import { toZonedTimestamp } from "@/lib/time";

// Owners and coordinators book visits. The database enforces the same rule (RLS),
// plus no double booking for every worker, valid times, archived clients, 1-2 workers
// and the status flow. Visit + workers are written in one transaction by an RPC.
const STAFF = ["owner", "coordinator"] as const;

function toArgs(input: VisitInput, timeZone: string) {
  return {
    p_client_id: input.clientId,
    // The first worker is the primary one (also kept in visits.worker_id for older clients).
    p_worker_ids: input.secondWorkerId ? [input.workerId, input.secondWorkerId] : [input.workerId],
    // Local wall-clock time in the agency's zone; Postgres converts it to an instant.
    p_starts_at: toZonedTimestamp(input.startsAt, timeZone),
    p_ends_at: toZonedTimestamp(input.endsAt, timeZone),
    p_notes: input.notes || undefined,
  };
}

export async function createVisit(input: VisitInput): Promise<ActionResult> {
  const parsed = visitSchema.safeParse(input);
  if (!parsed.success) return { ok: false, error: parsed.error.issues[0]?.message ?? "Check the form." };

  const { supabase, active } = await requireRole([...STAFF]);
  const { error } = await supabase.rpc("book_visit", {
    p_organization_id: active.organizationId,
    ...toArgs(parsed.data, active.timeZone),
  });
  if (error) return { ok: false, error: friendlyError(error) };

  revalidatePath("/visits");
  return { ok: true, message: "Visit booked." };
}

export async function updateVisit(visitId: string, input: VisitInput): Promise<ActionResult> {
  const parsed = visitSchema.safeParse(input);
  if (!parsed.success || !z.uuid().safeParse(visitId).success) return { ok: false, error: "Check the form." };

  const { supabase, active } = await requireRole([...STAFF]);
  const { error } = await supabase.rpc("update_visit", { p_visit_id: visitId, ...toArgs(parsed.data, active.timeZone) });
  if (error) return { ok: false, error: friendlyError(error) };

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

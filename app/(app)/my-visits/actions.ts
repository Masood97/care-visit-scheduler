"use server";

import { revalidatePath } from "next/cache";

import { friendlyError, type ActionResult } from "@/lib/errors";
import { locationSchema } from "@/lib/schemas";
import { requireRole } from "@/lib/session";

type LocationInput = { visitId: string; latitude: number; longitude: number };

// Workers change a visit only through these two database functions. The functions check
// the assigned worker, the time window and the 200 m radius themselves.
async function callVisitFunction(fn: "check_in" | "check_out", input: LocationInput): Promise<ActionResult> {
  const parsed = locationSchema.safeParse(input);
  if (!parsed.success) return { ok: false, error: "Your location couldn't be read. Allow location access and try again." };

  const { supabase } = await requireRole(["worker"]);
  const { error } = await supabase.rpc(fn, {
    p_visit_id: parsed.data.visitId,
    p_lat: parsed.data.latitude,
    p_lng: parsed.data.longitude,
  });
  if (error) return { ok: false, error: friendlyError(error) };

  revalidatePath("/my-visits");
  return { ok: true, message: fn === "check_in" ? "Checked in. Have a good visit." : "Checked out. Visit completed." };
}

export async function checkIn(input: LocationInput) {
  return callVisitFunction("check_in", input);
}

export async function checkOut(input: LocationInput) {
  return callVisitFunction("check_out", input);
}

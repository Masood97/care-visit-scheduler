"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";

import { friendlyError, type ActionResult } from "@/lib/errors";
import { clientSchema, type ClientInput } from "@/lib/schemas";
import { requireRole } from "@/lib/session";

const STAFF = ["owner", "coordinator"] as const;

function toRow(input: z.output<typeof clientSchema>) {
  return { full_name: input.fullName, address: input.address, latitude: input.latitude, longitude: input.longitude };
}

export async function createClientRecord(input: ClientInput): Promise<ActionResult> {
  const parsed = clientSchema.safeParse(input);
  if (!parsed.success) return { ok: false, error: parsed.error.issues[0]?.message ?? "Check the form." };

  const { supabase, active } = await requireRole([...STAFF]);
  const { error } = await supabase.from("clients").insert({ organization_id: active.organizationId, ...toRow(parsed.data) });
  if (error) return { ok: false, error: friendlyError(error) };

  revalidatePath("/clients");
  return { ok: true, message: "Client added." };
}

export async function updateClientRecord(clientId: string, input: ClientInput): Promise<ActionResult> {
  const parsed = clientSchema.safeParse(input);
  if (!parsed.success || !z.uuid().safeParse(clientId).success) return { ok: false, error: "Check the form." };

  const { supabase } = await requireRole([...STAFF]);
  const { data, error } = await supabase.from("clients").update(toRow(parsed.data)).eq("id", clientId).select("id");
  if (error) return { ok: false, error: friendlyError(error) };
  if (!data?.length) return { ok: false, error: "That client no longer exists or you can't edit it." };

  revalidatePath("/clients");
  return { ok: true, message: "Client updated." };
}

/** Archiving is how clients are retired: a client with visits can't be deleted. */
export async function setClientArchived(clientId: string, archived: boolean): Promise<ActionResult> {
  if (!z.uuid().safeParse(clientId).success) return { ok: false, error: "Unknown client." };

  const { supabase } = await requireRole([...STAFF]);
  const { data, error } = await supabase
    .from("clients")
    .update({ status: archived ? "archived" : "active" })
    .eq("id", clientId)
    .select("id");
  if (error) return { ok: false, error: friendlyError(error) };
  if (!data?.length) return { ok: false, error: "That client no longer exists or you can't change it." };

  revalidatePath("/clients");
  revalidatePath("/visits");
  return { ok: true, message: archived ? "Client archived." : "Client restored." };
}

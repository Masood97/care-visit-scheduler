"use server";

import { cookies } from "next/headers";
import { redirect } from "next/navigation";

import { ACTIVE_ORG_COOKIE, getSession } from "@/lib/session";
import { createClient } from "@/lib/supabase/server";

export async function signOut() {
  const supabase = await createClient();
  await supabase.auth.signOut();
  (await cookies()).delete(ACTIVE_ORG_COOKIE);
  redirect("/login");
}

/** Switch the organization a multi-agency user is working in. */
export async function switchOrganization(organizationId: string) {
  const { memberships } = await getSession();
  // Only organizations the user really belongs to (RLS already limited the list).
  if (!memberships.some((m) => m.organizationId === organizationId)) return;
  (await cookies()).set(ACTIVE_ORG_COOKIE, organizationId, { httpOnly: true, sameSite: "lax", path: "/" });
  redirect("/");
}

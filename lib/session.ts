import "server-only";

import { cookies } from "next/headers";
import { redirect } from "next/navigation";
import { cache } from "react";

import type { Database } from "@/lib/database.types";
import { createClient } from "@/lib/supabase/server";

export type Role = Database["public"]["Enums"]["member_role"];

export type Membership = {
  organizationId: string;
  organizationName: string;
  timeZone: string;
  role: Role;
  fullName: string;
};

export const ACTIVE_ORG_COOKIE = "active_org";

/**
 * The signed-in user, their memberships and the organization they are working in.
 * A user can belong to several organizations; the active one is kept in a cookie and
 * falls back to the first membership. Cached per request.
 */
export const getSession = cache(async () => {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) redirect("/login");

  // RLS returns only this user's own organizations.
  const { data: rows, error } = await supabase
    .from("organization_members")
    .select("organization_id, role, full_name, organizations(name, time_zone)")
    .eq("user_id", user.id)
    .order("organization_id");
  if (error) throw new Error("Could not load your organizations.");

  const memberships: Membership[] = (rows ?? []).flatMap((row) =>
    row.organizations
      ? [
          {
            organizationId: row.organization_id,
            organizationName: row.organizations.name,
            timeZone: row.organizations.time_zone,
            role: row.role,
            fullName: row.full_name,
          },
        ]
      : [],
  );

  const preferred = (await cookies()).get(ACTIVE_ORG_COOKIE)?.value;
  const active = memberships.find((m) => m.organizationId === preferred) ?? memberships[0] ?? null;

  return { supabase, user, memberships, active };
});

/** For pages that need an organization and one of the given roles; otherwise redirects home. */
export async function requireRole(roles: Role[]) {
  const session = await getSession();
  if (!session.active || !roles.includes(session.active.role)) redirect("/");
  return { ...session, active: session.active };
}

export function homePathFor(role: Role): string {
  if (role === "worker") return "/my-visits";
  if (role === "owner") return "/hours";
  return "/visits";
}

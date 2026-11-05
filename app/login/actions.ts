"use server";

import { redirect } from "next/navigation";

import type { ActionResult } from "@/lib/errors";
import { signInSchema, type SignInInput } from "@/lib/schemas";
import { createClient } from "@/lib/supabase/server";

export async function signIn(input: SignInInput): Promise<ActionResult> {
  const parsed = signInSchema.safeParse(input);
  if (!parsed.success) return { ok: false, error: "Enter your email and password." };

  const supabase = await createClient();
  const { error } = await supabase.auth.signInWithPassword(parsed.data);
  // Same message for unknown email and wrong password.
  if (error) return { ok: false, error: "That email and password don't match an account." };

  redirect("/");
}

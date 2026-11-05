import { redirect } from "next/navigation";

import { getSession, homePathFor } from "@/lib/session";

// Sends each user to the screen for their role in the active organization.
export default async function Home() {
  const { active } = await getSession();
  if (!active) {
    return (
      <main className="mx-auto max-w-md px-4 py-16 text-center">
        <h1 className="text-xl font-semibold">No organization yet</h1>
        <p className="mt-2 text-muted-foreground">
          Your account isn&apos;t a member of any agency. Ask an owner to add you.
        </p>
      </main>
    );
  }
  redirect(homePathFor(active.role));
}

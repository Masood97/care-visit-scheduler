import Link from "next/link";
import { redirect } from "next/navigation";

import { Button } from "@/components/ui/button";
import { getSession, type Role } from "@/lib/session";

import { signOut } from "./actions";
import { OrgSwitcher } from "./org-switcher";

const NAV: Record<Role, { href: string; label: string }[]> = {
  owner: [
    { href: "/hours", label: "Hours" },
    { href: "/visits", label: "Visits" },
    { href: "/clients", label: "Clients" },
  ],
  coordinator: [
    { href: "/visits", label: "Visits" },
    { href: "/clients", label: "Clients" },
    { href: "/hours", label: "Hours" },
  ],
  worker: [
    { href: "/my-visits", label: "My visits" },
    { href: "/hours", label: "My hours" },
  ],
};

export default async function AppLayout({ children }: LayoutProps<"/">) {
  const { active, memberships } = await getSession();
  if (!active) redirect("/");

  return (
    <div className="flex flex-1 flex-col">
      <header className="border-b">
        <div className="mx-auto flex w-full max-w-5xl flex-wrap items-center gap-x-4 gap-y-2 px-4 py-3">
          <Link href="/" className="font-semibold">
            Care Visits
          </Link>
          <OrgSwitcher
            options={memberships.map((m) => ({ id: m.organizationId, name: m.organizationName }))}
            activeId={active.organizationId}
          />
          <nav className="flex gap-3 text-sm">
            {NAV[active.role].map((item) => (
              <Link key={item.href} href={item.href} className="text-muted-foreground hover:text-foreground">
                {item.label}
              </Link>
            ))}
          </nav>
          <div className="ml-auto flex items-center gap-3 text-sm">
            <span className="hidden text-muted-foreground sm:inline">
              {active.fullName} · {active.role}
            </span>
            <form action={signOut}>
              <Button type="submit" variant="outline" size="sm">
                Sign out
              </Button>
            </form>
          </div>
        </div>
      </header>
      <main className="mx-auto w-full max-w-5xl flex-1 px-4 py-6">{children}</main>
    </div>
  );
}

"use client";

import { useTransition } from "react";

import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";

import { switchOrganization } from "./actions";

type Option = { id: string; name: string };

export function OrgSwitcher({ options, activeId }: { options: Option[]; activeId: string }) {
  const [pending, startTransition] = useTransition();

  if (options.length < 2) {
    return <span className="text-sm text-muted-foreground">{options[0]?.name}</span>;
  }

  return (
    <Select
      value={activeId}
      disabled={pending}
      onValueChange={(id) => startTransition(() => switchOrganization(id))}
    >
      <SelectTrigger size="sm" aria-label="Organization">
        <SelectValue />
      </SelectTrigger>
      <SelectContent>
        {options.map((o) => (
          <SelectItem key={o.id} value={o.id}>
            {o.name}
          </SelectItem>
        ))}
      </SelectContent>
    </Select>
  );
}

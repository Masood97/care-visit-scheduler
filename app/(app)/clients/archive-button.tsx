"use client";

import { useTransition } from "react";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";

import { setClientArchived } from "./actions";

export function ArchiveClientButton({ clientId, archived }: { clientId: string; archived: boolean }) {
  const [pending, startTransition] = useTransition();

  return (
    <Button
      variant="ghost"
      size="sm"
      disabled={pending}
      onClick={() =>
        startTransition(async () => {
          const result = await setClientArchived(clientId, !archived);
          if (result.ok) toast.success(result.message);
          else toast.error(result.error);
        })
      }
    >
      {archived ? "Restore" : "Archive"}
    </Button>
  );
}

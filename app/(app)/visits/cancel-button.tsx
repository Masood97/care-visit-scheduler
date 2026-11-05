"use client";

import { useTransition } from "react";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";

import { cancelVisit } from "./actions";

export function CancelVisitButton({ visitId }: { visitId: string }) {
  const [pending, startTransition] = useTransition();

  return (
    <Button
      variant="ghost"
      size="sm"
      disabled={pending}
      onClick={() => {
        if (!window.confirm("Cancel this visit? This can't be undone.")) return;
        startTransition(async () => {
          const result = await cancelVisit(visitId);
          if (result.ok) toast.success(result.message);
          else toast.error(result.error);
        });
      }}
    >
      Cancel
    </Button>
  );
}

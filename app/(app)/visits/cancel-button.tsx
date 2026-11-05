"use client";

import { useState, useTransition } from "react";
import { toast } from "sonner";

import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
  AlertDialogTrigger,
} from "@/components/ui/alert-dialog";
import { Button } from "@/components/ui/button";

import { cancelVisit } from "./actions";

export function CancelVisitButton({ visitId, summary }: { visitId: string; summary: string }) {
  const [open, setOpen] = useState(false);
  const [pending, startTransition] = useTransition();

  return (
    <AlertDialog open={open} onOpenChange={setOpen}>
      <AlertDialogTrigger asChild>
        <Button variant="ghost" size="sm" disabled={pending}>
          Cancel
        </Button>
      </AlertDialogTrigger>
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle>Cancel this visit?</AlertDialogTitle>
          <AlertDialogDescription>
            {summary}. A cancelled visit can&apos;t be scheduled again, and the time is freed for the workers.
          </AlertDialogDescription>
        </AlertDialogHeader>
        <AlertDialogFooter>
          <AlertDialogCancel>Keep visit</AlertDialogCancel>
          <AlertDialogAction
            disabled={pending}
            onClick={(event) => {
              event.preventDefault(); // keep the dialog open until the server answers
              startTransition(async () => {
                const result = await cancelVisit(visitId);
                if (result.ok) {
                  toast.success(result.message);
                  setOpen(false);
                } else {
                  toast.error(result.error);
                }
              });
            }}
          >
            {pending ? "Cancelling…" : "Cancel visit"}
          </AlertDialogAction>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  );
}

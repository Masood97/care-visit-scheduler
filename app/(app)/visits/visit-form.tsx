"use client";

import { zodResolver } from "@hookform/resolvers/zod";
import { useState, useTransition } from "react";
import { Controller, useForm } from "react-hook-form";
import { toast } from "sonner";

import { Alert, AlertDescription } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogTrigger } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Textarea } from "@/components/ui/textarea";
import { visitSchema, type VisitInput } from "@/lib/schemas";

import { createVisit, updateVisit } from "./actions";

type Option = { id: string; name: string };

type Props = {
  clients: Option[];
  workers: Option[];
  timeZone: string;
  /** Present when editing an existing visit. */
  visitId?: string;
  defaultValues?: Partial<VisitInput>;
  trigger: React.ReactNode;
};

export function VisitFormDialog({ clients, workers, timeZone, visitId, defaultValues, trigger }: Props) {
  const [open, setOpen] = useState(false);
  const [serverError, setServerError] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();
  const form = useForm<VisitInput>({
    resolver: zodResolver(visitSchema),
    defaultValues: { clientId: "", workerId: "", startsAt: "", endsAt: "", notes: "", ...defaultValues },
  });
  const { errors } = form.formState;

  const onSubmit = form.handleSubmit((values) => {
    setServerError(null);
    startTransition(async () => {
      const result = visitId ? await updateVisit(visitId, values) : await createVisit(values);
      if (!result.ok) {
        setServerError(result.error);
        return;
      }
      toast.success(result.message);
      setOpen(false);
      if (!visitId) form.reset();
    });
  });

  return (
    <Dialog
      open={open}
      onOpenChange={(next) => {
        setOpen(next);
        if (!next) setServerError(null);
      }}
    >
      <DialogTrigger asChild>{trigger}</DialogTrigger>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{visitId ? "Edit visit" : "Book a visit"}</DialogTitle>
        </DialogHeader>
        <form onSubmit={onSubmit} className="grid gap-4" noValidate>
          {serverError && (
            <Alert variant="destructive">
              <AlertDescription>{serverError}</AlertDescription>
            </Alert>
          )}

          <div className="grid gap-2">
            <Label htmlFor="clientId">Client</Label>
            <Controller
              control={form.control}
              name="clientId"
              render={({ field }) => (
                <Select value={field.value} onValueChange={field.onChange}>
                  <SelectTrigger id="clientId" className="w-full" aria-invalid={!!errors.clientId}>
                    <SelectValue placeholder="Choose a client" />
                  </SelectTrigger>
                  <SelectContent>
                    {clients.map((c) => (
                      <SelectItem key={c.id} value={c.id}>
                        {c.name}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              )}
            />
            {errors.clientId && <p className="text-sm text-destructive">{errors.clientId.message}</p>}
          </div>

          <div className="grid gap-2">
            <Label htmlFor="workerId">Worker</Label>
            <Controller
              control={form.control}
              name="workerId"
              render={({ field }) => (
                <Select value={field.value} onValueChange={field.onChange}>
                  <SelectTrigger id="workerId" className="w-full" aria-invalid={!!errors.workerId}>
                    <SelectValue placeholder="Choose a worker" />
                  </SelectTrigger>
                  <SelectContent>
                    {workers.map((w) => (
                      <SelectItem key={w.id} value={w.id}>
                        {w.name}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              )}
            />
            {errors.workerId && <p className="text-sm text-destructive">{errors.workerId.message}</p>}
          </div>

          <div className="grid gap-4 sm:grid-cols-2">
            <div className="grid gap-2">
              <Label htmlFor="startsAt">Starts</Label>
              <Input id="startsAt" type="datetime-local" {...form.register("startsAt")} aria-invalid={!!errors.startsAt} />
              {errors.startsAt && <p className="text-sm text-destructive">{errors.startsAt.message}</p>}
            </div>
            <div className="grid gap-2">
              <Label htmlFor="endsAt">Ends</Label>
              <Input id="endsAt" type="datetime-local" {...form.register("endsAt")} aria-invalid={!!errors.endsAt} />
              {errors.endsAt && <p className="text-sm text-destructive">{errors.endsAt.message}</p>}
            </div>
          </div>
          <p className="-mt-2 text-xs text-muted-foreground">Times are in the agency&apos;s time zone ({timeZone}).</p>

          <div className="grid gap-2">
            <Label htmlFor="notes">Notes</Label>
            <Textarea id="notes" rows={3} {...form.register("notes")} />
            {errors.notes && <p className="text-sm text-destructive">{errors.notes.message}</p>}
          </div>

          <Button type="submit" disabled={pending}>
            {pending ? "Saving…" : visitId ? "Save changes" : "Book visit"}
          </Button>
        </form>
      </DialogContent>
    </Dialog>
  );
}

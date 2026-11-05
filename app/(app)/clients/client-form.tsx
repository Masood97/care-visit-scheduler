"use client";

import { zodResolver } from "@hookform/resolvers/zod";
import { useState, useTransition } from "react";
import { useForm } from "react-hook-form";
import { toast } from "sonner";
import type { z } from "zod";

import { Alert, AlertDescription } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogTrigger } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { clientSchema, type ClientInput } from "@/lib/schemas";

import { createClientRecord, updateClientRecord } from "./actions";

type Props = {
  clientId?: string;
  defaultValues?: ClientInput;
  trigger: React.ReactNode;
};

export function ClientFormDialog({ clientId, defaultValues, trigger }: Props) {
  const [open, setOpen] = useState(false);
  const [serverError, setServerError] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();
  const form = useForm<ClientInput, unknown, z.output<typeof clientSchema>>({
    resolver: zodResolver(clientSchema),
    defaultValues: defaultValues ?? { fullName: "", address: "", latitude: "", longitude: "" },
  });
  const { errors } = form.formState;

  const onSubmit = form.handleSubmit(() => {
    setServerError(null);
    // Send the raw form values; the server action parses them with the same schema.
    const values = form.getValues();
    startTransition(async () => {
      const result = clientId ? await updateClientRecord(clientId, values) : await createClientRecord(values);
      if (!result.ok) {
        setServerError(result.error);
        return;
      }
      toast.success(result.message);
      setOpen(false);
      if (!clientId) form.reset();
    });
  });

  const field = (name: keyof ClientInput, label: string, props: React.ComponentProps<typeof Input> = {}) => (
    <div className="grid gap-2">
      <Label htmlFor={name}>{label}</Label>
      <Input id={name} {...props} {...form.register(name)} aria-invalid={!!errors[name]} />
      {errors[name] && <p className="text-sm text-destructive">{errors[name]?.message}</p>}
    </div>
  );

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
          <DialogTitle>{clientId ? "Edit client" : "Add a client"}</DialogTitle>
        </DialogHeader>
        <form onSubmit={onSubmit} className="grid gap-4" noValidate>
          {serverError && (
            <Alert variant="destructive">
              <AlertDescription>{serverError}</AlertDescription>
            </Alert>
          )}
          {field("fullName", "Full name")}
          {field("address", "Home address")}
          <div className="grid gap-4 sm:grid-cols-2">
            {field("latitude", "Latitude", { inputMode: "decimal", placeholder: "-33.8650" })}
            {field("longitude", "Longitude", { inputMode: "decimal", placeholder: "151.2094" })}
          </div>
          <p className="-mt-2 text-xs text-muted-foreground">
            The home&apos;s coordinates. Workers must be within 200 m of them to check in.
          </p>
          <Button type="submit" disabled={pending}>
            {pending ? "Saving…" : clientId ? "Save changes" : "Add client"}
          </Button>
        </form>
      </DialogContent>
    </Dialog>
  );
}

// Zod schemas shared by the forms (client-side validation with React Hook Form) and the
// server actions (validated again on the server). The database enforces the same rules;
// these just give faster, friendlier feedback.
import { z } from "zod";

const localDateTime = z
  .string()
  .regex(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/, "Enter a date and time.");

export const signInSchema = z.object({
  email: z.email("Enter a valid email address."),
  password: z.string().min(1, "Enter your password."),
});
export type SignInInput = z.infer<typeof signInSchema>;

export const visitSchema = z
  .object({
    clientId: z.uuid("Choose a client."),
    workerId: z.uuid("Choose a worker."),
    // Optional second worker for 2:1 support ("" = none).
    secondWorkerId: z.union([z.uuid(), z.literal("")]).optional(),
    startsAt: localDateTime,
    endsAt: localDateTime,
    notes: z.string().trim().max(500, "Keep notes under 500 characters.").optional(),
  })
  .refine((v) => !v.secondWorkerId || v.secondWorkerId !== v.workerId, {
    path: ["secondWorkerId"],
    message: "Choose two different workers.",
  })
  .refine((v) => v.endsAt > v.startsAt, { path: ["endsAt"], message: "The visit must end after it starts." })
  .refine(
    (v) => new Date(`${v.endsAt}:00Z`).getTime() - new Date(`${v.startsAt}:00Z`).getTime() <= 12 * 3600 * 1000,
    { path: ["endsAt"], message: "A visit can last at most 12 hours." },
  );
export type VisitInput = z.infer<typeof visitSchema>;

export const clientSchema = z.object({
  fullName: z.string().trim().min(1, "Enter the client's name.").max(120),
  address: z.string().trim().min(1, "Enter the home address.").max(200),
  latitude: z.coerce.number<string>().min(-90, "Latitude must be between -90 and 90.").max(90, "Latitude must be between -90 and 90."),
  longitude: z.coerce
    .number<string>()
    .min(-180, "Longitude must be between -180 and 180.")
    .max(180, "Longitude must be between -180 and 180."),
});
export type ClientInput = z.input<typeof clientSchema>;

export const locationSchema = z.object({
  visitId: z.uuid(),
  latitude: z.number().min(-90).max(90),
  longitude: z.number().min(-180).max(180),
});

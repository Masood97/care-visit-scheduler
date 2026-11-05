// Creates one demo agency with a sign-in for each role on a HOSTED project
// (staging or production), where supabase/seed.sql is never loaded.
//
// This writes data, not schema: no tables, policies or functions are touched.
// It needs the project's secret / service-role key, which is read from the environment
// only. Never commit it, never paste it into a file in this repo, and never echo it.
//
// Usage (PowerShell):
//   $env:SUPABASE_URL = "https://<project-ref>.supabase.co"
//   $env:SUPABASE_SECRET_KEY = "<secret or service_role key>"   # from the dashboard
//   $env:DEMO_PASSWORD = "<a strong password for the demo users>"
//   node scripts/create-demo-accounts.mjs
//
// Safe to re-run: it stops if the demo agency already exists.
import { createClient } from "@supabase/supabase-js";

const url = process.env.SUPABASE_URL;
const secretKey = process.env.SUPABASE_SECRET_KEY;
const password = process.env.DEMO_PASSWORD;

if (!url || !secretKey || !password) {
  console.error("Set SUPABASE_URL, SUPABASE_SECRET_KEY and DEMO_PASSWORD first (see the header of this file).");
  process.exit(1);
}
if (password.length < 10) {
  console.error("DEMO_PASSWORD must be at least 10 characters.");
  process.exit(1);
}

const db = createClient(url, secretKey, { auth: { persistSession: false, autoRefreshToken: false } });

const ORG = { name: "Bayside Demo Care", time_zone: "Australia/Sydney" };
const STAFF = [
  { email: "owner@bayside-demo.example", role: "owner", full_name: "Olivia Grant" },
  { email: "coordinator@bayside-demo.example", role: "coordinator", full_name: "Marcus Lee" },
  { email: "worker1@bayside-demo.example", role: "worker", full_name: "Hana Sato" },
  { email: "worker2@bayside-demo.example", role: "worker", full_name: "Diego Ruiz" },
];
// Fake people and addresses around a fictional Sydney suburb.
const CLIENTS = [
  { full_name: "Beatrice Collins", address: "12 Driftwood Lane, Bayside", latitude: -33.8568, longitude: 151.2153 },
  { full_name: "Arjun Mehta", address: "7 Kelp Street, Bayside", latitude: -33.8612, longitude: 151.2101 },
  { full_name: "Rosa Delgado", address: "31 Tidewater Road, Bayside", latitude: -33.8655, longitude: 151.2049 },
];

function fail(step, error) {
  console.error(`${step} failed: ${error.message ?? error}`);
  process.exit(1);
}

const { data: existing, error: lookupError } = await db.from("organizations").select("id").eq("name", ORG.name);
if (lookupError) fail("Looking up the demo agency", lookupError);
if (existing.length) {
  console.log(`"${ORG.name}" already exists; nothing to do.`);
  process.exit(0);
}

const { data: org, error: orgError } = await db.from("organizations").insert(ORG).select("id").single();
if (orgError) fail("Creating the agency", orgError);

const ids = {};
for (const person of STAFF) {
  const { data, error } = await db.auth.admin.createUser({ email: person.email, password, email_confirm: true });
  if (error) fail(`Creating ${person.email}`, error);
  ids[person.email] = data.user.id;
  const { error: memberError } = await db.from("organization_members").insert({
    organization_id: org.id,
    user_id: data.user.id,
    role: person.role,
    full_name: person.full_name,
  });
  if (memberError) fail(`Adding ${person.email} to the agency`, memberError);
}

const { data: clients, error: clientError } = await db
  .from("clients")
  .insert(CLIENTS.map((c) => ({ ...c, organization_id: org.id })))
  .select("id");
if (clientError) fail("Creating clients", clientError);

// Scheduled visits over the next week at 09:00 / 13:00 Sydney time, alternating workers.
const workers = [ids["worker1@bayside-demo.example"], ids["worker2@bayside-demo.example"]];
const sydneyToday = new Intl.DateTimeFormat("en-CA", { timeZone: ORG.time_zone }).format(new Date());
const visits = [];
for (let day = 1; day <= 7; day++) {
  const date = new Date(`${sydneyToday}T00:00:00Z`);
  date.setUTCDate(date.getUTCDate() + day);
  const d = date.toISOString().slice(0, 10);
  for (const [slot, hour] of [9, 13].entries()) {
    visits.push({
      organization_id: org.id,
      client_id: clients[(day + slot) % clients.length].id,
      worker_id: workers[(day + slot) % 2],
      starts_at: `${d} ${String(hour).padStart(2, "0")}:00 ${ORG.time_zone}`,
      ends_at: `${d} ${String(hour + 2).padStart(2, "0")}:00 ${ORG.time_zone}`,
      notes: slot === 0 ? "Morning personal care" : "Afternoon support",
    });
  }
}
const { error: visitError } = await db.from("visits").insert(visits);
if (visitError) fail("Booking visits", visitError);

console.log(`Created "${ORG.name}" with ${STAFF.length} users, ${CLIENTS.length} clients and ${visits.length} visits.`);
console.log("Sign-ins (password = DEMO_PASSWORD):");
for (const p of STAFF) console.log(`  ${p.role.padEnd(11)} ${p.email}`);

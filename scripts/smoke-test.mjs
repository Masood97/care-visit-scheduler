// Smoke test (local only, needs the seed): signs in as each seeded role with @supabase/ssr
// (the same cookie format the app uses), then requests pages from the running Next server
// with those cookies and checks what each role sees and where it is redirected.
//
// Usage: SB_URL=http://127.0.0.1:54321 SB_KEY=<publishable key> node scripts/smoke-test.mjs
//        (app running on http://localhost:3000, or set APP_URL)
import { createRequire } from "node:module";
const require = createRequire(import.meta.url);
const { createServerClient } = require("@supabase/ssr");

const APP = process.env.APP_URL ?? "http://localhost:3000";
const URL_ = process.env.SB_URL;
const KEY = process.env.SB_KEY;

async function cookiesFor(email) {
  const jar = new Map();
  const sb = createServerClient(URL_, KEY, {
    cookies: {
      getAll: () => [...jar].map(([name, value]) => ({ name, value })),
      setAll: (list) => list.forEach(({ name, value }) => jar.set(name, value)),
    },
  });
  const { error } = await sb.auth.signInWithPassword({ email, password: "Password123!" });
  if (error) throw new Error(`${email}: ${error.message}`);
  return [...jar].map(([n, v]) => `${n}=${v}`).join("; ");
}

async function get(path, cookie) {
  const res = await fetch(APP + path, { headers: cookie ? { cookie } : {}, redirect: "manual" });
  const body = res.status === 200 ? await res.text() : "";
  return { status: res.status, location: res.headers.get("location"), body };
}

const checks = [];
function check(name, ok) { checks.push([ok ? "PASS" : "FAIL", name]); }

// Signed out
let r = await get("/");
check("signed out: / redirects to /login", r.status === 307 && r.location?.endsWith("/login"));
r = await get("/login");
check("signed out: /login renders the form", r.status === 200 && r.body.includes("Sign in"));

// Coordinator (Harbour)
const coord = await cookiesFor("coordinator@harbour.example");
r = await get("/", coord);
check("coordinator: / goes to /visits", r.status === 307 && r.location?.endsWith("/visits"));
r = await get("/visits", coord);
check("coordinator: week view lists Harbour clients", r.status === 200 && r.body.includes("Book visit") && /Margaret Ellis|Tomasz Nowak|Priya Raman|Aiyana Brooks|Desmond Hale/.test(r.body));
check("coordinator: no Pennine data on the page", !/Eileen Thornton|Gareth Pryce|Nadia Haddad|Wilfred Ashby|Sunita Patel/.test(r.body));
r = await get("/clients", coord);
check("coordinator: clients page lists 5 Harbour clients", r.status === 200 && (r.body.match(/Harbourside/g) ?? []).length >= 5);
r = await get("/hours", coord);
check("coordinator: hours report shows both workers", r.status === 200 && r.body.includes("Wei Chen") && r.body.includes("Sofia Alvarez"));
r = await get("/my-visits", coord);
check("coordinator: worker page redirects away", r.status === 307);

// Worker 1 (Pennine)
const worker = await cookiesFor("worker1@pennine.example");
r = await get("/", worker);
check("worker: / goes to /my-visits", r.status === 307 && r.location?.endsWith("/my-visits"));
r = await get("/my-visits", worker);
check("worker: sees own visits with a check-out button (in-progress visit)", r.status === 200 && r.body.includes("Check out"));
check("worker: does not see worker 2's clients only", !r.body.includes("Rescheduled by family"));
r = await get("/hours", worker);
check("worker: sees only their own hours", r.status === 200 && r.body.includes("Kwame Mensah") && !r.body.includes("Ellie Ward"));
r = await get("/visits", worker);
check("worker: coordinator page redirects away", r.status === 307);

// Owner (Harbour)
const owner = await cookiesFor("owner@harbour.example");
r = await get("/", owner);
check("owner: / goes to /hours", r.status === 307 && r.location?.endsWith("/hours"));
r = await get("/hours", owner);
check("owner: weekly hours report renders totals", r.status === 200 && r.body.includes("Weekly hours") && r.body.includes("Total"));

for (const [s, n] of checks) console.log(`${s}  ${n}`);
process.exit(checks.some(([s]) => s === "FAIL") ? 1 : 0);

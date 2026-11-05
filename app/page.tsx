// Placeholder home page. The role-based screens arrive in feature/web-app (#5).
export default function Home() {
  return (
    <main className="mx-auto flex w-full max-w-2xl flex-1 flex-col justify-center gap-3 px-4 py-16">
      <h1 className="text-2xl font-semibold tracking-tight">Care Visits</h1>
      <p className="text-muted-foreground">
        Home-care visit scheduling for agencies, coordinators and support workers.
      </p>
    </main>
  );
}

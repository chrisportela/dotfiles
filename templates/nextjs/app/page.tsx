import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardFooter,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";

export default function Home() {
  return (
    <main className="flex min-h-screen flex-col items-center justify-center p-8">
      <div className="w-full max-w-md space-y-6">
        <div className="space-y-2 text-center">
          <h1 className="text-3xl font-bold tracking-tight">
            Next.js + pnpm
          </h1>
          <p className="text-muted-foreground">
            Template with Tailwind CSS and shadcn/ui
          </p>
        </div>

        <Card>
          <CardHeader>
            <CardTitle>Welcome</CardTitle>
            <CardDescription>
              This template includes TypeScript, Prisma, Better Auth, Vitest,
              and Playwright. Add more components with the shadcn CLI.
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-2">
            <p className="text-sm text-muted-foreground">
              Run <code className="rounded bg-muted px-1.5 py-0.5 font-mono text-xs">pnpm dlx shadcn@latest add &lt;component&gt;</code> to add
              more shadcn components.
            </p>
          </CardContent>
          <CardFooter className="flex gap-2">
            <Button>Get started</Button>
            <Button variant="outline">Learn more</Button>
          </CardFooter>
        </Card>
      </div>
    </main>
  );
}

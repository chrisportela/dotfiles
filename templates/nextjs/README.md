# Next.js + pnpm Template

A Next.js project template with TypeScript, pnpm, and Nix flakes for reproducible development environments.

## Features

- ⚡ Next.js 15 with App Router
- 📦 pnpm for fast, efficient package management
- 🔷 TypeScript with strict mode enabled
- 🐚 Nix flake for reproducible development environment
- 🔄 direnv integration for automatic environment activation
- 🎨 [Tailwind CSS](https://tailwindcss.com/) for styling
- 🧩 [shadcn/ui](https://ui.shadcn.com/) (new-york style) with Button and Card; add more via CLI
- 🗄️ PostgreSQL database with Prisma ORM
- 🔐 Better Auth for authentication (email/password)
- 🧪 Vitest for unit testing
- 🎭 Playwright for end-to-end testing

## Prerequisites

- [Nix](https://nixos.org/download.html) installed
- [direnv](https://direnv.net/) installed and configured
- pnpm (will be provided by the Nix shell)

## Getting Started

### 1. Create the project from the template

```bash
nix flake new my-app -t github:chrisportela/dotfiles#nextjs-pnpm
cd my-app
```

Or from a local dotfiles clone:

```bash
nix flake new my-app -t /path/to/dotfiles#nextjs-pnpm
cd my-app
```

### 2. Initialize the Nix environment

The template references the dotfiles repository. Make sure the flake input is accessible:

```bash
# The flake.nix references: github:chrisportela/dotfiles
# If you need to use a local path instead, edit flake.nix:
#   dotfiles.url = "path:/path/to/dotfiles";
```

### 3. Allow direnv

```bash
direnv allow
```

This will automatically activate the Nix shell when you enter the directory.

### 4. Setup PostgreSQL

The template includes a `setup_postgres` function in `.envrc` to help you start a local PostgreSQL instance:

```bash
setup_postgres
```

This will:
- Create a local PostgreSQL data directory (`.postgres-data/`)
- Initialize the database if needed
- Start PostgreSQL on port 5432
- Set the `DATABASE_URL` environment variable

### 5. Install dependencies

```bash
pnpm install
```

### 6. Setup Environment Variables

Copy the example environment file:

```bash
cp .env.example .env
```

Update `DATABASE_URL` and `NEXT_PUBLIC_APP_URL` as needed.

### 7. Setup Prisma and Database

Generate the Prisma client and push the schema to your database:

```bash
pnpm db:generate
pnpm db:push
```

This will create the Better Auth tables (User, Account, Session, Verification) in your database.

### 8. Run the development server

```bash
pnpm dev
```

Open [http://localhost:3000](http://localhost:3000) in your browser to see the result.

### 9. Production build (Nix)

Build the production app with Nix:

```bash
nix build
# or
nix build .#production
```

The result is in `result/`: built `.next`, `node_modules`, and a `result/bin/start` script. Run the production server with:

```bash
./result/bin/start
```

The production package uses Nixpkgs pnpm support (`pnpm.fetchDeps` and `pnpm.configHook`) for offline-reproducible builds. You must commit `pnpm-lock.yaml` (run `pnpm install` first if you don't have it). The first time you run `nix build`, it will fail and print a SHA256 hash; copy that hash into `flake.nix` as the `pnpmDeps.hash` value (replace the empty string), then run `nix build` again.

## Project Structure

```
.
├── app/                  # Next.js App Router directory
│   ├── layout.tsx        # Root layout
│   ├── page.tsx          # Home page
│   └── globals.css       # Global styles
├── app/
│   ├── api/
│   │   └── auth/
│   │       └── [...all]/
│   │           └── route.ts  # Better Auth API handler
│   ├── dashboard/
│   │   └── page.tsx      # Protected dashboard page
│   ├── sign-in/
│   │   └── page.tsx      # Sign in page
│   └── sign-up/
│       └── page.tsx      # Sign up page
├── e2e/                  # Playwright end-to-end tests
│   └── example.spec.ts   # Example E2E test
├── lib/
│   ├── auth.ts           # Better Auth server configuration
│   └── auth-client.ts    # Better Auth client configuration
├── prisma/               # Prisma configuration
│   └── schema.prisma     # Database schema (includes Better Auth tables)
├── proxy.ts              # Next.js proxy for route protection
├── flake.nix             # Nix flake configuration
├── .envrc                 # direnv configuration
├── package.json           # pnpm package configuration
├── tsconfig.json          # TypeScript configuration
├── next.config.mjs        # Next.js configuration
├── vitest.config.ts       # Vitest configuration
├── vitest.setup.ts        # Vitest setup file
├── playwright.config.ts   # Playwright configuration
└── README.md              # This file
```

## Available Scripts

### Development
- `pnpm dev` - Start the development server
- `pnpm build` - Build the production application
- `pnpm start` - Start the production server
- `pnpm lint` - Run ESLint

### Database (Prisma 7)
- `pnpm db:generate` - Generate Prisma Client (outputs to `prisma/generated/prisma/client`)
- `pnpm db:push` - Push schema changes to database (dev only)
- `pnpm db:migrate` - Create and run migrations
- `pnpm db:studio` - Open Prisma Studio (database GUI)

**Note:** The `prisma` CLI is provided by Nix for consistent deployment. The generated client uses the new Prisma 7 output path structure.

### Testing
- `pnpm test` - Run Vitest unit tests
- `pnpm test:ui` - Run Vitest with UI
- `pnpm test:e2e` - Run Playwright end-to-end tests
- `pnpm test:e2e:ui` - Run Playwright tests with UI

## Customizing the Template

### Changing the dotfiles reference

If you want to use a different dotfiles repository or a local path, edit `flake.nix`:

```nix
dotfiles = {
  url = "github:your-username/your-dotfiles";
  # or
  url = "path:/path/to/your/dotfiles";
};
```

### Adding shadcn/ui components

The template includes `components.json` for the shadcn CLI. Add more components with:

```bash
pnpm dlx shadcn@latest add input
pnpm dlx shadcn@latest add dialog
```

Components are added under `components/ui/`. See [shadcn/ui docs](https://ui.shadcn.com/docs).

### Adding dependencies

Add packages to `package.json` and run `pnpm install`. For Nix packages, add them to the `buildInputs` in `flake.nix`.

### Modifying the shell

Edit `flake.nix` to add or remove packages from the development environment. The shell hook in `flake.nix` can be customized to show different messages or set environment variables.

## Testing

### Unit Tests with Vitest

Create test files with `.test.ts` or `.test.tsx` extensions:

```typescript
import { describe, it, expect } from 'vitest';

describe('Example', () => {
  it('should work', () => {
    expect(1 + 1).toBe(2);
  });
});
```

Run tests with `pnpm test` or `pnpm test:ui` for the interactive UI.

### End-to-End Tests with Playwright

E2E tests are located in the `e2e/` directory. The example test checks that the homepage loads correctly.

Run E2E tests with `pnpm test:e2e` or `pnpm test:e2e:ui` for the interactive UI.

## Database Setup

The template uses Prisma 7 with PostgreSQL. The database schema is defined in `prisma/schema.prisma` and includes Better Auth tables.

**Note:** Prisma binaries are provided by the Nix shell for consistent deployment. The `prisma` CLI command uses the Nix-provided version.

1. Make sure PostgreSQL is running (use `setup_postgres` from `.envrc`)
2. Set your `DATABASE_URL` environment variable (automatically set by `setup_postgres`)
3. Generate the Prisma client: `pnpm db:generate`
   - This generates the client to `prisma/generated/prisma/client` (Prisma 7 requirement)
4. Push your schema: `pnpm db:push` (for development) or create migrations: `pnpm db:migrate`

You can open Prisma Studio to view and edit your database: `pnpm db:studio`

## Authentication Setup

The template includes Better Auth with email/password authentication.

### Features

- Email/password sign up and sign in
- Session management
- Protected routes (see `app/dashboard/page.tsx` for an example)
- Route protection via proxy (`proxy.ts`)

### Usage

1. **Server-side authentication check:**
   ```typescript
   import { auth } from "@/lib/auth";
   import { headers } from "next/headers";
   
   const session = await auth.api.getSession({
     headers: await headers(),
   });
   ```

2. **Client-side authentication:**
   ```typescript
   import { authClient } from "@/lib/auth-client";
   
   await authClient.signIn.email({ email, password });
   await authClient.signUp.email({ email, password, name });
   await authClient.signOut();
   ```

3. **Protected routes:**
   - The `proxy.ts` file protects `/dashboard` routes
   - Individual pages can check authentication (see `app/dashboard/page.tsx`)

### Auth Pages

- `/sign-in` - Sign in page
- `/sign-up` - Sign up page
- `/dashboard` - Protected dashboard (requires authentication)

## Learn More

- [Next.js Documentation](https://nextjs.org/docs)
- [pnpm Documentation](https://pnpm.io/)
- [Prisma Documentation](https://www.prisma.io/docs)
- [Better Auth Documentation](https://better-auth.com/docs)
- [Vitest Documentation](https://vitest.dev/)
- [Playwright Documentation](https://playwright.dev/)
- [Nix Flakes](https://nixos.wiki/wiki/Flakes)
- [direnv Documentation](https://direnv.net/)

## License

This template is part of the dotfiles repository and follows the same license.

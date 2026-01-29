# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Next.js 16 application using the App Router with TypeScript, PostgreSQL, and Better Auth for authentication. It's built with pnpm as the package manager and uses Nix flakes for reproducible development environments.

## Common Commands

### Development
```bash
pnpm dev          # Start development server (http://localhost:3000)
pnpm build        # Build for production
pnpm start        # Start production server
pnpm lint         # Run ESLint
```

### Database (Prisma 7)
```bash
pnpm db:generate  # Generate Prisma Client (outputs to prisma/generated/prisma/client)
pnpm db:push      # Push schema changes to database (development only)
pnpm db:migrate   # Create and run migrations
pnpm db:studio    # Open Prisma Studio GUI
```

### Testing
```bash
pnpm test         # Run Vitest unit tests
pnpm test:ui      # Run Vitest with interactive UI
pnpm test:e2e     # Run Playwright end-to-end tests
pnpm test:e2e:ui  # Run Playwright with interactive UI
```

## Architecture

### Prisma 7 Custom Output Path

This project uses **Prisma 7** which requires a custom output directory. The Prisma client is generated to `prisma/generated/prisma/client` (not the default `node_modules/.prisma/client`).

**Critical**: Always import the Prisma client from the custom path:
```typescript
import { PrismaClient } from "@/prisma/generated/prisma/client";
```

The Prisma configuration is in `prisma.config.ts` which loads the `DATABASE_URL` from environment variables.

### Better Auth Integration

Authentication is handled by Better Auth with email/password support:

- **Server-side auth**: Configured in `lib/auth.ts` using the Prisma adapter
- **Client-side auth**: Would be in `lib/auth-client.ts` (if created)
- **Database schema**: Better Auth tables (User, Account, Session, Verification) are defined in `prisma/schema.prisma`

The auth instance uses the custom Prisma client path and the `nextCookies()` plugin must be the last plugin in the array.

### Path Aliases

TypeScript is configured with `@/*` mapping to the root directory:
```typescript
import { auth } from "@/lib/auth";
import { cn } from "@/lib/utils";
```

### UI Components

The project uses shadcn/ui (new-york style) with Tailwind CSS v4:
- Components are in `components/ui/`
- Currently includes: Button, Card
- Add more via: `pnpm dlx shadcn@latest add <component-name>`
- Uses the `cn()` utility from `lib/utils.ts` for class merging

### Development Environment

The project uses Nix flakes with direnv for automatic environment activation. A `setup_postgres` function in `.envrc` helps start a local PostgreSQL instance. All development tools (Node.js, pnpm, PostgreSQL, Prisma CLI) are provided by the Nix environment.

## Key Files

- `prisma.config.ts` - Prisma 7 configuration with custom paths
- `lib/auth.ts` - Better Auth server configuration with Prisma adapter
- `lib/utils.ts` - Utility functions (cn for classnames)
- `app/layout.tsx` - Root layout component
- `components.json` - shadcn/ui configuration

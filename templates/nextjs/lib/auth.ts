import { betterAuth } from "better-auth";
import { prismaAdapter } from "better-auth/adapters/prisma";
import { PrismaClient } from "@/prisma/generated/prisma/client";
import { nextCookies } from "better-auth/next-js";
import { PrismaPg } from "@prisma/adapter-pg";

const pgAdapter = new PrismaPg(process.env.DATABASE_URL);
const prisma = new PrismaClient({
  adapter: pgAdapter,
  log: [
    // "query",
    "info",
    "warn",
    "error"
  ],
});

export const auth = betterAuth({
  database: prismaAdapter(prisma, {
    provider: "postgresql",
  }),
  emailAndPassword: {
    enabled: true,
  },
  plugins: [
    nextCookies(), // Make sure this is the last plugin in the array
  ],
});

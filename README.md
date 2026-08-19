# Ganpati Chanda Manager

Mobile-first Next.js application connected to Supabase project `tgttvufbzlfitrvfrytl`.

## Run

```bash
pnpm install
pnpm dev
```

The checked-in `.env.example` documents required values. `.env.local` contains only the project URL, publishable browser key, and Mandal UUID. Never place a Supabase secret/service key or payment secret in a `NEXT_PUBLIC_` variable.

The current payment adapter is deliberately marked mock mode. It does not create a donation or claim a payment succeeded. To enable payments, add server-only `SUPABASE_SECRET_KEY`, `PAYMENT_KEY_SECRET`, and `PAYMENT_WEBHOOK_SECRET`, then implement the selected gateway adapter and webhook verification.

## Supabase

The live project contains tenant-scoped tables, RLS policies, immutable ledger/audit protections, safe public aggregate/receipt RPCs, and a private `mandal-documents` bucket limited to PDF/JPEG/PNG/WebP files up to 5 MB.

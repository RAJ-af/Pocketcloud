# Supabase setup guide

## 1. Create a separate project

Create a new project for PocketCloud in an organization you control; do not reuse a project belonging to another app. For users in India, `ap-south-1` is a sensible starting region. Project creation may have costs based on organization/plan; confirm the current quote first.

## 2. Apply the database migration

### Dashboard route

1. Open the project's SQL Editor.
2. Review `supabase/migrations/20261024000100_pocketcloud_core.sql` in this repository.
3. Paste the complete migration and run it once on the new project.
4. Inspect errors; don't rerun partial sections blindly. If a run partially applied, reconcile live schema/migration history first.

### Supabase CLI route

From the repo root, install the official Supabase CLI, then:

```bash
supabase login
supabase link --project-ref YOUR_PROJECT_REF
supabase db push
```

Use the CLI route when the migration is tracked in the project. For fresh untracked setup, verify `supabase migration list` and test on staging before production.

After application, verify all seven tables and RLS policies exist, `anon` has no application table access, and `authenticated` has only intended grants. Check Database → Publications includes `public.signaling_messages`. Run Security and Performance Advisors and resolve unexpected findings.

## 3. Deploy the Edge Functions

The source files are in `supabase/functions/redeem-pairing/index.ts` and `supabase/functions/revoke-device/index.ts`. The included `supabase/config.toml` requires JWT verification for both functions.

```bash
supabase functions deploy redeem-pairing
supabase functions deploy revoke-device
```

Supabase supplies `SUPABASE_URL`, `SUPABASE_ANON_KEY` in the Edge Function environment in many projects; code also falls back to `SUPABASE_PUBLISHABLE_KEY`. Confirm the environment variables exist. The function uses `SUPABASE_SERVICE_ROLE_KEY` only on the server to invoke the atomic database RPC. **Never paste or commit that key into Flutter, this repo, a GitHub variable passed to Flutter, an issue, or a chat.** Do not disable JWT verification for these functions.

Test both functions with a logged-out caller (401), invalid input (400), valid session with invalid code/device (generic rejection), valid code (only one successful redemption), and device revoke (device and pair state changes).

## 4. Configure Authentication

Open Authentication → Sign In / Providers and enable Email. For public release, enable email confirmation, configure SMTP, password/reset rate limits and recovery redirect URLs as needed. Test sign-up, confirmation, sign-in, reset and sign-out against the live project.

## 5. Configure Flutter/GitHub

Get the project URL and **publishable key** from Project Settings. Add repository Actions **Variables**:

- `SUPABASE_URL`
- `SUPABASE_PUBLISHABLE_KEY`

Optional TURN configuration only after you operate a TURN service:

- Variable `TURN_URL`
- Secrets `TURN_USERNAME`, `TURN_CREDENTIAL`

The `--dart-define` values are compiled into the app. Never put long-lived server secrets there. A TURN production integration should mint short-lived credentials server-side.

## 6. Post-setup verification

- Verify `private.has_current_consent()` returns false unless the current Terms and Privacy versions are each accepted.
- Verify app clients cannot update consent records, change `pairing_codes.status`, alter `expires_at`, insert `device_pairs`, or un-revoke devices.
- Verify pairing RPC is executable only by `service_role`.
- Use two test accounts for cross-account attempts and two physical devices for signalling/transfer. Test stale heartbeat, revoke mid-session and network loss.
- Review current Supabase quotas for Auth email, Realtime, database, storage and bandwidth. A $0 project-creation quote is not an uptime or unlimited-usage guarantee.

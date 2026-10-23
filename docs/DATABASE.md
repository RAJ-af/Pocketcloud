# Database and RLS specification

Migration file: `supabase/migrations/20261024000100_pocketcloud_core.sql`.

## Tables

| Table | Purpose | Client access model |
|---|---|---|
| `profiles` | Minimal self profile | Read/insert/update own row after current consent |
| `user_consents` | Append-only policy decisions | Read own rows, insert own decision; no update/delete grants; timestamp comes from Postgres |
| `devices` | Device inventory/status | Read own rows; create as client only; update limited columns on own rows after current consent; database trigger stamps activity timestamps |
| `pairing_codes` | Digest, expiry and redemption state | Insert only `(owner_id, server_device_id, code_hash, can_upload)`; cannot select, update, delete or specify lifecycle/timestamp columns |
| `device_pairs` | Pair and per-pair capabilities | Select own rows (app queries active only); no insert; can set `revoked_at` only on own active pair to revoke it |
| `signaling_messages` | SDP/ICE/hangup control plane | Read/insert/delete with owner and active-pair checks; payload size constrained |
| `connection_events` | Small diagnostics | Read own events and insert own permitted event types; do not include file names/content or secrets |

## Authorization invariants

1. RLS is enabled on every exposed application table; `anon` and broad `authenticated` privileges are revoked first and re-granted narrowly.
2. Data visibility is owner-scoped via `(select auth.uid())` and row relationships. `TO authenticated` alone is not authorization.
3. Update policies have both `USING` and `WITH CHECK`. User-editable `raw_user_meta_data` is not used for authorization.
4. Client cannot directly create `device_pairs` or alter the state of pairing codes. `pairing_codes.expires_at`, status, `created_at` and usage timestamps come from database defaults/functions.
5. `redeem_pairing_code_atomic(p_owner_id,p_code_hash,p_client_device_id)` row-locks a single pending code; checks current policy consent, expiry, account ownership, server-enabled state, client/server difference and revocation; inserts or reactivates the unique pair; and marks the code used in one transaction.
6. `revoke_device_atomic(p_owner_id,p_device_id)` revokes a device, its active pairs and its pending pairing codes in one transaction.
7. Both public-schema RPCs use `SECURITY INVOKER`, a fixed empty `search_path`, and execution rights only for `service_role`. Their execute grants are revoked from `PUBLIC`, `anon` and `authenticated`. Only the JWT-verifying Edge Functions should call them.
8. `private.has_current_consent()` checks the most recent terms and privacy decisions for the exact current version. `private.owner_has_current_consent(uuid)` performs the equivalent check for the trusted RPC. Increment `LegalVersions` and SQL versions together when text changes.
9. A device activity trigger overwrites client-provided `last_seen_at` and `updated_at` with database time. Presence older than 90 seconds is considered stale by the UI/client.
10. Signalling rows are small control-plane metadata; file content is transferred over WebRTC and is not written to database rows.

## Explicit grants and new Data API defaults

New Supabase projects created from 2026-05-30 onward do not automatically expose newly created public tables to the Data API by default. The migration explicitly grants required privileges and revokes `anon`; this is separate from row-level visibility. If a table cannot be reached despite grants/RLS, check the project's Data API exposure settings.

## Operational notes

- Apply in a clean staging project first, inspect the schema and table grants, run Supabase Security/Performance Advisors, and verify all table-level grants with a privileged SQL query.
- Configure the `supabase_realtime` publication for `public.signaling_messages`. It must never contain file content.
- Signal rows are deleted by recipients after processing when possible. A scheduled stale-row cleanup/retention task is not included yet.
- `is_online` is a hint only; client code checks `last_seen_at` age and actual WebRTC state. A server-side stale-status/pruning job should be added before production.
- Account deletion must be performed through a trusted admin workflow that revokes sessions/pairs, removes user-owned records according to retention policy and deletes the Auth user. Never put admin credentials in the client.

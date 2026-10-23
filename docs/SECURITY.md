# Security threat model and review

## Assets

Supabase Auth session; profile and consent history; device IDs, names and state; pairing-code digests; pair permissions; WebRTC signalling; local vault files; TURN credentials.

## Trust boundaries

- Flutter is an untrusted client. A modified APK can call Supabase APIs directly, so the UI is not an authorization boundary.
- Supabase Auth authenticates account identity. Postgres RLS and narrowly granted privileges decide what a session may read or write.
- Edge Functions verify the caller's JWT with Auth before privileged operations. The service-role key must remain only in Supabase-managed server environment.
- Realtime carries SDP/ICE/hangup metadata and is not the data plane for file contents.
- The server phone is an endpoint. Malware, physical access or an unlocked device can expose files available to the app.
- TURN can see network metadata and traffic volume. WebRTC data-channel transport encrypts peer payloads while the connection is established.

## Implemented source mitigations

- App client only accepts project URL and publishable key. Never add `service_role`, `sb_secret_...`, database password or Supabase personal access token to Flutter or GitHub client variables.
- RLS is enabled on all seven app tables. `anon` grants are revoked; `authenticated` has explicit least-privilege table/column grants. Ownership is checked alongside role.
- Consent is recorded append-only. The current Terms version and current Privacy version must both have their latest accepted decision. SQL policies and pairing RPC check consent, not just the UI.
- Installation UUID is held in secure local storage, not user-editable/synced metadata. The database stamps device activity times.
- Pairing codes use 12 characters from a restricted alphabet, only their SHA-256 digest is stored, DB time supplies five-minute expiry, and an atomic row-locked function creates the pair and marks the code used.
- The client cannot insert or edit `device_pairs`, read/alter pairing codes after creation, or set code status/expiry. Revocation is a JWT-verified server operation. Client-side emergency revocation of an active pairing is allowed by setting only `revoked_at` on the user's own active pair.
- Both atomic public-schema RPCs use `SECURITY INVOKER` and are executable only by `service_role`. Their execution grants are revoked from `PUBLIC`, `anon` and `authenticated`.
- Pair permissions are checked on the receiving endpoint. Upload is off by default, received names are sanitized, file size is capped at 25 MiB and SHA-256 is verified.
- Signalling payload size is constrained. No shell execution, arbitrary remote command endpoint or full-filesystem browser is included.
- Connected client periodically re-reads pair/device status. If verification fails for 30 seconds, it disconnects; network/offline timing may delay revocation enforcement.

## Remaining risks / release blockers

- None of the RLS, Edge Function or transfer controls has had an external penetration test. Do not treat these docs as a security certification.
- The backend is not deployed and no live advisor output is available yet. Apply the SQL in a clean staging project, inspect generated policies/grants, run Supabase Security and Performance Advisors, then test direct API calls as multiple accounts.
- Devices on the same account share account-level authorization. The prototype does not cryptographically attest a device's local installation ID as a separate identity, so a compromised session within the same account can impersonate sibling device metadata. A stronger production model needs per-device keys/tokens and server-verified signatures.
- Current signal policies establish pair membership within the account but do not provide hardware-backed device identity. Treat an account compromise as a compromise of all devices under that account.
- No TURN relay is bundled; direct WebRTC may fail behind restrictive NAT. Avoid embedding permanent TURN credentials in the APK.
- The app has no foreground service, guaranteed background host, fixed metadata retention, signalling pruning task, server-side rate limiting or self-service account deletion.
- App-private storage is not independently encrypted by PocketCloud. Rely on Android device encryption/screen lock as configured, and do not use this MVP for highly sensitive storage without a threat-model update.
- In-app Terms and Privacy are drafts. Legal review and operator contact information are required before public distribution.

## Adversarial test checklist

1. Authenticate as Account A and try reading/updating Account B IDs on all tables.
2. Attempt client `INSERT/UPDATE/DELETE` against `device_pairs` and `pairing_codes` lifecycle columns; expect privilege/RLS denial.
3. Replay one pairing code and redeem it concurrently from two client installs; expect only one successful redemption.
4. Submit malformed, expired and cross-account pairing codes; expect generic client-facing errors.
5. Change only `policy_version` on a client, omit consent, reject consent, and record an older accepted decision; protected actions must stay denied until both current versions are accepted.
6. Try invalid sender/recipient IDs, oversized signalling JSON and stale messages.
7. Send upload without permission, file with path traversal name, oversized size, reordered chunks, size mismatch and digest mismatch; receiver must reject and write no partial file.
8. Revoke a device during transfer; verify session ends on refresh/lease expiry, and document worst-case delay when signalling is unreachable.
9. Run GitHub CI, install the artifact and repeat all tests on real devices.

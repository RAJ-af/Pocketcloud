# Delivery and verification checklist

Updated: 2026-10-24. A checked source item means it exists in the repository, not that it has passed runtime verification.

## Product and documentation
- [x] Feature inventory and release acceptance criteria written.
- [x] Architecture and network-data-flow documentation written.
- [x] UI specification written for the dark/mango-lime design system.
- [x] Terms and Privacy drafts exist as docs and readable in-app policy text.
- [x] Threat model and RLS intent documented.
- [x] Supabase setup, test plan and known limitations documented.

## Database and cloud source
- [x] Migration draft creates seven app tables and indexes.
- [x] RLS enabled on every app table.
- [x] Explicit table/column grants, with `anon` access revoked.
- [x] Current consent is checked in protected RLS paths and trusted pairing RPC.
- [x] Database stamps device activity timestamps.
- [x] Client cannot insert/update pair lifecycle rows directly.
- [x] Single-use code redemption and revocation transactions exist in SQL source.
- [x] JWT-verifying Edge Function source included for pair redemption and device revocation.
- [ ] Live Supabase project created after destination organization is confirmed.
- [ ] Apply migration in live/staging project and verify schema, grants and RLS.
- [ ] Deploy both Edge Functions and test no-JWT/invalid-JWT/valid-JWT paths.
- [ ] Run Security Advisor and Performance Advisor; resolve findings.
- [ ] Race/replay, cross-account, direct Data API and RLS denial tests passed.

## Flutter application source
- [x] Auth, consent onboarding, home, devices, vault and security screens written.
- [x] Full policy reader added to onboarding; consent writes both current versions.
- [x] Secure-storage per-install ID source.
- [x] Server mode UI + app-process WebRTC listener source; listener reattaches when the home screen reloads an enabled host.
- [x] QR scan/manual code path wired to pairing Edge Function.
- [x] WebRTC signalling and transfer protocol source with permission/size/hash checks; transfer chunk authorization checks both paired device IDs.
- [x] Bounded retry and remote access lease source.
- [x] Collision-safe received-file naming source.
- [x] Migrated file selection to file_picker v13 APIs and share sheet calls to share_plus current API.
- [ ] Run `dart format` and `dart analyze` with Flutter stable SDK.
- [x] Added VaultStore filename-sanitization unit tests.
- [ ] Run `flutter test`; add service/protocol unit tests beyond current smoke tests.
- [ ] Verify dependency/API compatibility in a real Android build.
- [ ] Test pair/transfer scenarios using two physical devices.

## Security / operations
- [x] No service-role key is checked into the Flutter code or example config.
- [x] No broad Android all-files permission requested.
- [x] Upload default is off; 25 MiB per-file transport limit.
- [x] Limitations include no background service, no TURN host and no external security audit.
- [ ] Review every table grant/policy using privileged database queries after live deploy.
- [ ] Realtime works with only `signaling_messages` published.
- [ ] Configure retention/pruning, rate limits, abuse protection and account deletion.
- [ ] Obtain legal review and add operator contact / data-request details.
- [ ] External security/penetration test before public release.

## Build and delivery
- [x] GitHub Actions workflow for Android release artifact included.
- [x] Idempotent manifest helper included.
- [ ] Generate and commit `pubspec.lock` through Flutter dependency resolution.
- [ ] GitHub Actions build completed successfully.
- [ ] Install APK and inspect device logs on target Android device(s).
- [ ] Verify release APK against same Wi-Fi and separate-network scenarios.

## Current honest status

**Not production-ready and not yet runtime verified.** The local execution environment does not have Flutter/Dart installed. The new Supabase project has not been created because the user must confirm the organization destination; cloud schema, Edge Functions and live security advisors are therefore still pending. Source checks do not substitute for real Android networking tests.

# Feature inventory and acceptance criteria

**Status terms:** “Source implemented” means code is present but not necessarily compiled or run. “Pending verification” means the feature must not be advertised as production-ready.

| Feature | Design / acceptance criteria | Current state |
|---|---|---|
| Email/password auth | Sign up, sign in, password reset request, sign out; clear errors | Source implemented; needs live Auth SMTP/confirmation test |
| Consent onboarding | Full Terms and Privacy text, independent acknowledgement checkboxes, accept/reject audit, exact version; block current version on rejection | Source implemented; backend policies enforce current accepted version; runtime pending |
| Device registration | Stable local secure-storage installation UUID; server/client role; DB-generated activity timestamps | Source implemented; multi-install runtime pending |
| Server mode | Explicit toggle; host listens for signalling while app process is alive | Source implemented; no foreground service; keep app open |
| QR/code pairing | 12 secure random characters; digest at rest; DB clock five-minute TTL; same account; one-use atomic redemption | UI/Edge/RPC source implemented; live migration + Edge deploy + hostile test pending |
| Revoke device | JWT-verified Edge Function; DB transaction marks device and its pairs revoked | Source implemented; live function validation pending |
| Local vault | User-picked files copied to app-private storage; list, share/export, delete; path-safe names | Source implemented; real device tests pending |
| Remote signalling | Offer/answer/ICE/hangup through Supabase Realtime with per-pair RLS | Source implemented; end-to-end network tests pending |
| Remote listing/download | Pair permission checked by receiver; one transfer at a time; maximum 25 MiB/file; ordered chunks and SHA-256 verification | Source implemented; WebRTC plugin/API + devices unverified |
| Remote upload | Off by default; only allowed when owner enables it; receiving server validates size/hash/name and acknowledges final write | Source implemented; runtime tests pending |
| Auto reconnect | Single bounded retry schedule, lease checks, refresh pair state; stop retries for revoked/invalid pair | Source implemented, maximum 8 attempts then explicit Retry; runtime pending |
| Online status | Heartbeat every 30 seconds, UI treats heartbeat older than 90 seconds as stale | Source implemented; background/abrupt kill behaviour requires testing |
| Background hosting | Service survives screen-off, Doze, reboot and OEM battery killing | Not implemented; explicit release blocker |
| TURN relay | Fallback behind restrictive NAT/carrier networks | Configuration hook only; no TURN service supplied |
| GitHub release APK | CI analysis, widget tests, release APK, artifact upload | Workflow source included; not run yet in this environment |

## MVP release gate

Do not claim production readiness until all of the following pass: Flutter compile/analyze/tests; migration application and advisor review; Edge Function deploy and auth tests; account isolation; code expiration/replay/concurrency; two-device WebRTC on same and different networks; TURN path; upload denial and permission revocation during transfer; APK installation; long-duration Android behaviour; legal/privacy review.

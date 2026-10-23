# PocketCloud Privacy Policy

**Draft version: 2026-10-24.** This is a product draft, not legal advice. Review it for the countries where the app will be distributed before release.

## Information we process

- Account identity: email address and authentication/session data handled by Supabase Auth.
- Consent history: policy type/version, accepted or rejected decision, timestamp and source.
- Device metadata: random app installation identifier, device label, platform, server/client role, last-seen/online status and revocation state.
- Connection metadata: small WebRTC signalling records (session description/candidate details), connection status and diagnostic event type. Network addresses may be visible to peer networking and TURN infrastructure.
- Files: the app stores files the user explicitly chooses in app-private storage. The intended data path for remote transfer is a WebRTC data channel, not Supabase Postgres. The app must not upload file content to Supabase without a separate explicit feature and consent.

## How information is used

To authenticate, register and pair the user's devices, establish peer connections, apply per-pair permissions, record legal decisions, diagnose connection problems, prevent abuse and provide the core service.

## Sharing and service providers

Supabase provides hosted authentication, database and realtime signalling. A TURN relay may be used to establish peer connectivity. TURN infrastructure can observe IP address, connection times, traffic volume and routing metadata, but WebRTC encrypts traffic between peers. Providers operate under their own terms and privacy practices.

## Storage and retention

App vault files remain on the server phone unless the user shares/exports them or transfers them to another paired device. Account/device/signalling/event data remains in Supabase according to the configured retention and backup settings. The production implementation should expire old signalling rows and stale online states. No exact retention period is promised until the deployed service configuration is fixed and published. App-private storage is not a separate app-layer encrypted vault; protection relies on Android/device storage encryption and screen-lock settings.

## Your choices

You may decline Terms/Privacy consent and stop setup. You can sign out, disable server mode and revoke device pairings. Account deletion must be requested through a support/admin workflow until self-service deletion is implemented. Revocation is checked by a best-effort active-session lease (10-second polling, disconnect after 30 seconds without a successful authorization check), but it is not instantaneous if a device is offline. This behavior still requires real-device testing.

## Security

We use row-level access policies and encrypted network transport where implemented. No internet service can guarantee absolute security or uninterrupted availability. Protect your email account, device screen lock and server phone physically.

## Children's privacy

The service is not designed for children to use without an appropriate parent/guardian and applicable legal compliance. The production policy must specify a minimum age after legal review.

## Changes and contact

This policy can change. Material updates should increment the policy version and require a fresh in-app decision. Add an operator contact email and company/legal identity before public distribution; these are intentionally not invented in this draft.

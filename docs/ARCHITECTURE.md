# Architecture

## Components

- **Flutter app**: authentication, local vault, device management, pairing UI and user consent. Uses only the Supabase project URL + publishable key.
- **Supabase Auth**: email/password identity and session/JWT management. Authorization is based on `auth.uid()` and ownership policies, never editable `user_metadata` claims.
- **Supabase Postgres**: profile, consent audit, device inventory, pairing state, small WebRTC signalling records and connection event metadata.
- **Supabase Realtime**: delivers inserted signalling messages. It must not carry file contents. Configure replication only for `public.signaling_messages`.
- **WebRTC peer connection**: encrypted data channel between two signed-in devices for direct data movement when network traversal works.
- **TURN relay (separate deployment)**: needed when direct peer-to-peer connection cannot cross NAT or carrier networks. Supabase does not automatically give this app a TURN server.
- **Android app-private vault**: user-selected files are copied into the app's private document directory. Unselected files and other apps' private data are out of scope.

## Device flow

1. User signs up/signs in using Supabase Auth.
2. User accepts current Terms and Privacy versions; both decisions are appended to `user_consents`.
3. App creates/updates its `devices` row using an installation ID held locally. Every device has a unique ID.
4. Server mode is turned on explicitly. The server creates a cryptographically random pairing code, stores only its SHA-256 digest, and expires it after five minutes.
5. Another device, signed into the same account in this MVP, redeems the code. The backend checks expiry/status/ownership before creating `device_pairs`.
6. The peers exchange small SDP and ICE records through Realtime. Payload size is bounded; file data must never be written to signalling rows.
7. Device revoke updates the device, active pair rows and pending code rows in one Edge Function + SQL transaction. The peer service refreshes pair/device state every 10 seconds while connected and disconnects if it cannot verify access for 30 seconds. Database revocation alone cannot terminate a peer connection already established if the device is disconnected from signalling, so local session timeout is required.

## Reconnection strategy

Use one reconnect coordinator per client peer, stepped bounded backoff (2, 4, 8, 16, 30 and 60 second delays), a maximum of eight attempts, one in-flight attempt and an explicit Retry action after the limit. Rebuild the peer connection after failed/closed state, clear stale ICE/SDP messages and refresh current pair permissions before trying again. Do not run independent reconnect timers from each widget.

## Data path

Signalling is control plane; file payload is data plane. The intended flow is:

`Flutter client -> WebRTC data channel -> remote peer -> app-private vault`

If ICE cannot establish a direct path, the configured TURN service relays encrypted WebRTC traffic. If no TURN service is configured, some carrier/Wi-Fi networks will fail. Automatic reconnect cannot recover from a powered-off phone, absent internet, force-stop, or an OS that has killed the app.

## MVP concurrency and service lifecycle

The current host listener handles one active peer at a time. On clean hangup or peer failure it clears the in-memory peer so another eligible paired device can offer a connection. This is not a concurrent multi-client server. No Android foreground service is bundled: keep the host app in the foreground for best results; screen-off, Doze, process death and OEM battery rules may suspend the listener/heartbeat.

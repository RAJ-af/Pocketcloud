/// Plain-language in-app drafts. These are product text, not jurisdiction-specific legal advice.
class PolicyText {
  static const terms = r'''POCKETCLOUD TERMS & CONDITIONS
Draft version: 2026-10-24

1. What PocketCloud does
PocketCloud helps you connect devices that you own or are authorised to administer. Your chosen server phone stores files in the app's private vault. Supabase is used for account authentication, device records, pairing, connection signalling and consent records. The service is an MVP and availability is not guaranteed.

2. Acceptable use
Use PocketCloud only with devices and files you own or have permission to access. Do not use it for covert surveillance, unauthorised data collection, access-control bypass, malware distribution, unlawful access, exposing someone else's files, abusing pairing codes or overloading the service. Do not attempt to bypass device permissions.

3. Your responsibilities
Keep your account credentials private, use a secure device screen lock, protect the server phone physically, review connected devices, disable server mode when not needed, revoke lost devices and keep separate backups of important files. You are responsible for following privacy, copyright, data-protection and computer-access laws that apply to your use.

4. Files and third-party services
Files you select are stored in the app-private vault. Remote transfer is designed to use an encrypted WebRTC data channel rather than store file content in Supabase database tables. Connection metadata and network details may be processed by Supabase and, where configured, a TURN relay provider. Third-party services have their own availability and terms.

5. Availability and risk
The app may fail on particular Android versions, devices, Wi-Fi networks or mobile carriers. A powered-off phone, missing internet, force-stop or operating-system restrictions can make the server unavailable. Automatic reconnection does not guarantee recovery. Do not rely on PocketCloud as your only backup, emergency service, safety-critical system or enterprise-grade backup product.

6. Device access and termination
You are responsible for approving pairings and reviewing permissions. You can sign out, stop server mode, revoke device access and stop using the app. A self-service account deletion feature is not yet available in this MVP; account deletion requires the documented trusted support/admin workflow.

7. Security limits
We use row-level database policies and encrypted transport where implemented, but no internet-connected system can promise absolute security, continuous service or zero risk. Report suspected vulnerabilities to the operator once a support contact is published.

8. Changes and legal review
This text is a draft and is not legal advice. Before public release, the operator must publish its legal identity and contact details, define age requirements, governing law, consumer rights, dispute handling, liability provisions and applicable data-protection notices with qualified legal counsel. Material policy changes should use a new version and request a fresh user decision.
''';

  static const privacy = r'''POCKETCLOUD PRIVACY POLICY
Draft version: 2026-10-24

1. Information processed
• Account data: email address and authentication/session information handled by Supabase Auth.
• Consent history: policy type and version, accepted or rejected decision, database timestamp and source.
• Device metadata: random installation identifier, device label, platform, server/client role, heartbeat/last-seen state and revocation state.
• Connection data: WebRTC session-description and ICE-candidate signalling, recipient/sender device IDs, connection status and limited diagnostic event types. Peer networking and TURN infrastructure may process IP addresses, connection times, traffic volume and routing metadata.
• Files: files you explicitly import into the app-private vault and files you request to receive. File contents are intended to travel through the encrypted peer data channel and are not intended to be stored in Supabase tables.

2. Why the information is used
We process this information to sign you in, register and pair devices, enforce pair permissions, negotiate peer connections, store your legal-policy decisions, diagnose connection failures, reduce abuse and provide the app's core features.

3. Services and sharing
Supabase provides authentication, database and realtime signalling. A TURN relay may forward encrypted WebRTC traffic when direct networking fails. Those providers may process service and network metadata under their own privacy practices. The app does not sell your file contents. We do not claim that no metadata is visible to providers or network peers.

4. Storage and retention
Vault files stay on the device unless you transfer, share, export or delete them. Account and device metadata, consent records, signalling rows and diagnostics are kept in the configured Supabase project. Signalling cleanup and fixed retention periods must be configured and verified before public release; this draft does not promise a specific retention duration. App-private storage is not an additional app-layer encrypted vault. Android's device encryption may protect it when device encryption and screen lock are enabled, depending on OS/device configuration.

5. Choices and controls
You can decline these policies and stop setup, sign out, disable server mode and revoke paired-device access. Revocation is checked periodically while a connection is active; an unreachable peer may take time to receive the update and session lease expiry is a fallback, so immediate termination cannot be guaranteed. Account deletion currently requires a trusted support/admin process, which must revoke pairings and delete associated data according to a published retention policy.

6. Security
The app uses owner-scoped database policies and secure local storage for installation identity. Peer payload transport uses WebRTC encryption when a peer connection is established. Absolute security cannot be guaranteed. Keep your account password private, maintain device security, and avoid exposing pairing codes.

7. Children and age
The appropriate minimum age and rules for parental consent must be determined through legal review for the countries where the app is offered. This draft does not establish a final age policy.

8. Policy changes and contact
A material change should increment the in-app policy version and request a new decision. Before release, the operator must add its legal identity, privacy contact email, data-protection contact where applicable, and a process for privacy requests. Those details are intentionally not invented in this draft.
''';
}

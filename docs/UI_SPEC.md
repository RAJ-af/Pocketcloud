# UI design specification

## Direction

Premium utility dashboard, designed for a small phone screen first. It should look like a lightweight personal infrastructure tool, not a generic file manager or WhatsApp clone.

- Background: near-black `#0B0E12`.
- Surfaces: `#141920` and `#1B232B`, restrained borders `#29333D`.
- Primary accent: mango-lime `#D9FF67`; secondary status accent aqua `#67E8D6`.
- Typography: strong geometric hierarchy with large short headline, regular readable copy, high-contrast labels. No decorative script fonts.
- Shape language: 14–27 px radii, compact status badges, 1 px outlines, large tap targets.
- Motion: animate server-state indicator and transitions subtly; never make connectivity depend on animation. Respect reduced-motion settings in a future polish pass.

## Screens

1. **Setup required**: clear message when the project URL/key are absent; never crash because the app was built before cloud setup.
2. **Auth**: email/password, sign-up, forgot password, clear loading/error states; no fake social-login buttons.
3. **Legal onboarding**: visible Terms and Privacy text; separate checkboxes; no permissions pre-granted; explicit accept and decline; log decision versions and times.
4. **Home**: status hero, Start/Stop Server, network and registration metrics, Cloud Library / Connected Devices / Security actions, plain warning for background/network limitations.
5. **Devices**: registered device list, role/status, pairing code QR + expiry, revoke confirmation, errors and empty state.
6. **Cloud library**: explicit import into app-private storage, file size, export/share/delete, empty and error states.
7. **Security**: clear statements about encryption, permission boundaries and current limitations.

## Interaction rules

- All touch targets should be at least 44–48 logical pixels where practical.
- Loading states disable duplicate submits; backend errors should not silently appear as success.
- Destructive actions require confirmation and a success/failure result.
- Do not display `is_online` as definitive reachability. Combine a recent heartbeat with real connection state when available.
- Permission prompts appear in context, exactly when the feature is invoked, explaining why the permission is needed.
- Maintain accessible contrast, text scaling, screen-reader labels, keyboard navigation where applicable, and responsive layouts before app-store release.

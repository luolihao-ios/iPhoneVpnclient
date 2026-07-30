# Windows Runtime Diagnostics Design

## Goal

Keep the existing Windows sing-box command-line integration and align it with
the recent mobile iteration's operational feedback: trustworthy connection
state, actionable diagnostics, and complete logs. This work does not add a
native Windows TUN or libbox runtime.

## Cross-platform product parity

Windows must expose the same product content as the current Android and iOS
iterations: the same feature entry points, user-visible data, connection and
health states, diagnostics, and log feedback. This is content and behavioral
parity, not a requirement to duplicate the mobile layout.

The desktop build will retain Windows-appropriate presentation: persistent
desktop navigation, denser multi-column node information, a clear always-visible
connection action area, and mouse/keyboard-friendly controls. Shared Flutter
features are audited against their desktop branches; a mobile-only native API is
translated to the equivalent desktop behavior where available, or surfaced as a
clear desktop diagnostic when it has no command-line equivalent.

## Scope

- Track the desktop sing-box process lifecycle in `SingBoxController`.
- Publish a connected state only after the launched process survives startup.
- Record the active PID, start time, configuration path, last exit code, and
  recent core logs for diagnostics.
- Add a Windows-specific diagnostics path to the existing Logs page.
- Preserve the Android and iOS native VPN diagnostics paths.
- Audit recent mobile UI and feature iterations against Windows behavior, then
  add or adapt missing desktop entry points, content, and feedback without
  forcing a phone-oriented layout on Windows.
- Add focused regression tests and run Flutter formatting, tests, and analysis.

## Non-goals

- Native Windows VPN/TUN support or a libbox binding.
- Taking over a sing-box process left over from a previous application run.
- Changes to the user's pending Android work.
- Reworking the existing subscription, routing, or UI layout behavior.
- Copying mobile screen composition, Android permission flows, or iOS tunnel
  controls into the Windows desktop UI.

## Runtime lifecycle

`SingBoxController` remains the single owner of the desktop process. It will
store metadata for the current and most recently completed run: PID, start
time, generated config path, exit code, and a bounded log buffer.

When connecting, the controller will write the generated config, launch
sing-box, and verify that the process has not exited during a short startup
window. Only then will it emit the connected state. An immediate process exit
will emit a disconnected state with the exit code and retain the captured core
logs, so `AppProvider` never reports a false successful connection.

An expected disconnect invalidates the active run before terminating the
process. A natural exit from the active run emits a disconnected state and its
exit code. In either case, `AppProvider` clears displayed traffic data;
unexpected exits are written to the application log.

On a fresh Windows app initialization, the provider restores persisted
subscription data and route mode as today but leaves runtime state disconnected.
It does not attach to an already-running external `sing-box.exe` process.

## Diagnostics and logs

The Logs page dispatches diagnostics by platform. On Windows it will inspect
the desktop controller and report:

- whether the configured sing-box executable exists;
- whether this controller has an active, live process and its PID;
- the active configuration file path and whether it exists;
- expected mixed/HTTP/SOCKS/API port availability;
- the most recent process exit code and start time when available;
- a bounded tail of captured sing-box output.

Diagnostics are appended to the existing provider logs, so they are visible in
the Logs page and included in the existing log export. Android and iOS keep
their MethodChannel-backed diagnostic implementations unchanged.

## Desktop feature audit

The implementation begins with a parity matrix covering recently introduced
mobile capabilities. Each item is classified as shared Flutter behavior,
Windows command-line behavior, or native-mobile-only behavior. Shared behavior
must be available on Windows with desktop-appropriate layout. Command-line
behavior is completed in the desktop controller. Native-only features keep their
mobile implementation and gain explanatory Windows diagnostics only when an
otherwise-visible action would be misleading.

## Testing

Introduce test seams around process launch, file checks, and port inspection
as needed to make the desktop controller deterministic. Regression tests cover
successful startup, immediate exit, expected disconnect, unexpected exit, and
Windows diagnostic dispatch from the Logs page. Existing mobile service tests
remain unchanged.

Verification consists of `dart format`, focused Flutter tests, and `flutter
analyze`. A Windows build may be added when the local Windows toolchain is
available, but is not required to validate the Dart behavior.

# Debugging iOS on a Real Device

How to find out what the keyboard did inside a real app — WeChat, Safari,
Notes — rather than inside a test harness.

## Why this exists

A custom keyboard is the hardest kind of iOS target to debug. It runs as a
separate process owned by whichever app is in the foreground, it cannot be
launched by a debugger, it has no settings screen, and it is killed and
respawned constantly. On top of that, everything in this project's failure
paths is designed to degrade rather than to stop:

| Failure | What the user sees | What used to be recorded |
|---|---|---|
| App Group entitlement missing | Voice results never arrive | Nothing |
| `NSFileCoordinator` write fails | Voice results never arrive | Nothing |
| librime cannot open the shared schema | Ten candidate words | A short badge |
| Host drops an insertion | Missing characters | Nothing |

`scripts/test-ios-device.sh` cannot help with any of it. It is an acceptance
gate: it runs the whole suite, including the WhisperKit download, and reports
pass or fail. That is the right shape for proving a release and the wrong shape
for asking "why did nothing happen when I tapped the mic key in WeChat".

## The loop

```zsh
# 1. Build a Debug bundle and install app + keyboard on the connected iPhone.
zsh scripts/debug-ios-device.sh

# 2. Open the app once. Rime deploys, and the shared container is created.
#    Diagnostics → type the name of the app you are about to test into
#    "Current channel", and turn on the switches you need.

# 3. Use the keyboard in that app, normally, for as long as it takes.

# 4. Read what happened.
zsh scripts/ios-diagnostics.sh pull
```

Nothing has to be tethered during step 3, which is the point: the bug can
happen while the phone is in someone's hand.

### Script reference

| Command | Purpose |
|---|---|
| `zsh scripts/debug-ios-device.sh` | Debug build, install, launch. `VIBEVOICE_DEVICE` picks a device, `VIBEVOICE_LAUNCH=0` installs without launching. |
| `zsh scripts/ios-diagnostics.sh pull` | Copy both processes' event logs off the device and print them merged by time. |
| `zsh scripts/ios-diagnostics.sh watch` | Observe the bridge's Darwin notification live, so handoff timing is visible without touching either process. |
| `zsh scripts/ios-diagnostics.sh state` | List the App Group container. Answers "did the keyboard ever reach the shared container". |
| `zsh scripts/ios-diagnostics.sh crashes` | Pull crash reports. |

## How the events get off the device

Every event goes to two places, because neither alone is enough.

`os_log`, under subsystem `app.vibevoice.oss`, with one category per area
(`lifecycle`, `host`, `bridge`, `rime`, `insertion`, `voice`, `model`). Visible
in Console.app with the device selected. **`log stream` on the command line no
longer supports iOS devices**, so this is a GUI-only route; do not spend time
looking for the flag, it was removed.

A JSON Lines file per process in the App Group container, which is what the
scripts read:

```
group.app.vibevoice.oss.shared/Diagnostics/app.jsonl
group.app.vibevoice.oss.shared/Diagnostics/keyboard.jsonl
```

Two files rather than one is deliberate. A shared file would need
`NSFileCoordinator` on every event, and coordinating from a keyboard extension
is exactly the operation that fails when the App Group entitlement is missing —
the case the log exists to diagnose. The reader interleaves them by timestamp.

The file is written with `completeUntilFirstUserAuthentication`, not the
`completeFileProtection` the voice bridge uses. Complete protection makes a file
unreadable to the device's file-transfer service, so `devicectl device copy
from` fails on it — try it on `VoiceBridge/voice-bridge.v2.json` and you get
`POSIX error 1`. Weakening the class for diagnostics is only acceptable because
of the next section.

## What may never be logged

**No event may carry what the user typed, said, or transcribed.** Text enters a
log only through `MobileLog.fingerprint(_:)`, which reduces it to a length and a
four-byte digest:

```
text=len=6 sha=1a2b3c4d
```

That is enough to prove the transcript the app produced is the text the keyboard
inserted, and enough to prove an insertion did or did not land, without either
string being stored. `DiagnosticsTests.testFingerprintDoesNotContainTheText`
enforces it. Keep that test passing: it is the only thing standing between a
pullable diagnostics file and a keylogger.

`os_log` redacts dynamic strings by default, and this layer marks its fields
`.public` to defeat that — a log full of `<private>` is worth nothing. That is
safe only under the same rule.

## Identifying a channel

iOS tells a keyboard extension nothing about its host. There is no public API
for the host bundle identifier, so `if host == "WeChat"` cannot be written and
no amount of searching will turn one up.

What iOS does expose is the shape of the text field: its `UITextInputTraits`,
and how much of the document the proxy will answer questions about. That is what
actually differs between hosts, and it is what breaks insertion — an app with
its own text engine publishes different traits and a different context window
than a plain UIKit field. `HostChannel` fingerprints that shape into a short
stable `id`, logged as `channel=`.

So a channel is identified two ways at once, and you want both:

- `channel=1f3a9c02` — mechanical, exact, meaningless to a human.
- `[WeChat]` — the label you typed into Diagnostics before switching apps.

A bug that reproduces under one `channel=` and not another is a
channel-specific bug. If it reproduces under every `channel=`, the host is not
the variable and the label is a red herring.

## Insertion checking

Off by default; turn it on in Diagnostics. After every insertion the keyboard
re-reads `documentContextBeforeInput` one run-loop turn later and classifies
what it finds:

| Outcome | Meaning |
|---|---|
| `landed` | The document ends with what was inserted. |
| `missing` | The document did not change. The host dropped the insertion. |
| `diverged` | The document changed into something else. The host rewrote or relocated the text — the signature of an app running its own input pipeline. |
| `unverifiable` | The host answers no context questions. Normal without Full Access. |

It costs an extra cross-process round trip per insertion, which is why it is
opt-in. It is also the only way to tell a host that silently drops text from a
keyboard that never sent any, so turn it on before arguing about either.

`missing` and `diverged` are logged at error level; `landed` only appears when
verbose events are on.

## Reading a session

A healthy session, from a cold start, looks like this:

```
app/lifecycle      app.launched build=63 storage=app group
app/bridge         store.opened appGroup=true coordinated=true
app/rime           app.deployed schema=vibe_pinyin ms=812
keyboard/lifecycle keyboard.loaded build=63 fullAccess=true storage=app group
keyboard/bridge    store.opened appGroup=true coordinated=true
keyboard/rime      keyboard.engine tier=sharedContainer ms=430
keyboard/host      document.attached channel=1f3a9c02 [WeChat] fullAccess=true ctxBefore=true
keyboard/bridge    state.changed from=idle to=requested target=9d2f1a04
app/voice          phase.changed from=idle to=recording
app/model          transcribe.finished audioMs=2100 ms=740 processed=len=9 sha=...
app/bridge         state.changed from=processing to=ready text=len=9 sha=...
keyboard/bridge    delivery.inserted request=... text=len=9 sha=... ageMs=1830
```

The lines that mean something is wrong:

| Line | Diagnosis |
|---|---|
| `store.opened appGroup=false` | The installed build has no App Group entitlement. Both processes are isolated; dictation can never cross. Check the provisioning profile actually granted it, not just that Xcode displays the capability. |
| `keyboard.engine tier=localSandbox` | The keyboard could not reach the shared schema and deployed its own copy. Typing works; learning is not shared with the app. `reason=` says why. |
| `keyboard.engine tier=prototype` | Ten-word lexicon. The keyboard will look like it has forgotten Chinese. `reason=` carries both failures. |
| `keyboard/rime` never appears | The keyboard extension has never run. It is not enabled in Settings, or it is crashing during the handshake — check `crashes`. |
| `delivery.deferred reason=keyboard has no document identity` | The proxy returned no document. The transcript needs an explicit mic tap. |
| `insert.verified outcome=missing` | This host discards what the keyboard inserts. Compare `channel=` against a host where it works. |
| `write.uncoordinated` | The bridge write never reached the file the other process reads. |
| `state.changed to=ready` with no later `delivery.*` | The app finished but the keyboard never picked it up. Confirm the extension is still alive with `state`, and that the signal fired with `watch`. |

If the merged log has no `keyboard/` lines at all, stop reading it and run
`zsh scripts/ios-diagnostics.sh state`. The absence of
`Rime/KeyboardUser` in the App Group container proves the extension has never
successfully opened librime against the shared container, which is a much
earlier failure than anything the log can describe.

## The trap that hides in `documentIdentifier`

The first thing this tooling found was a crash in the build it was added to.

`UITextDocumentProxy.documentIdentifier` is declared `nonnull` in
`UIInputViewController.h`, so Swift imports it as a non-optional `UUID`. The host
proxy returns nil anyway — while the extension handshake is incomplete, and
while iOS is restarting PlugInKit. Swift bridges that nil into a non-optional
`UUID` and traps:

```
EXC_BREAKPOINT / SIGTRAP
  UUID._unconditionallyBridgeFromObjectiveC(_:)
  KeyboardViewController.syncWithHostDocument()
  KeyboardViewController.textDidChange(_:)
```

That is `VibeVoiceKeyboard-2026-07-29-141238.ips`, pulled with
`zsh scripts/ios-diagnostics.sh crashes`. It explains a state the source
otherwise cannot: `currentDocumentID` was declared and read but never assigned,
which made the automatic-insertion path dead code. The assignment had been
written, it crashed the extension, and it was removed rather than fixed.

Read the property through key-value coding instead, so nil stays representable:

```swift
let getter = #selector(getter: UITextDocumentProxy.documentIdentifier)
guard proxy.responds(to: getter) else { return nil }
return proxy.value(forKey: NSStringFromSelector(getter)) as? UUID
```

The same reasoning already applies to `isSecureTextEntry`, which
`refreshPrivacyState` deliberately does not read. Treat every non-optional
property on that proxy as a lie until a device says otherwise.

## Turning the switches off

Verbose events cover every keystroke and insertion check adds a round trip to
each one. Both are session tools. Turn them off in Diagnostics when the
investigation is over; the durable file is capped at 512 KB and trims its oldest
half, so nothing runs away, but the battery cost is real.

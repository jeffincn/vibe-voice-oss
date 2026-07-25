# iPhone 14 Pro Max / iOS 26 Acceptance

This checklist closes the physical-device-only gaps that simulators cannot prove.
The target device is Buzz, an iPhone 14 Pro Max currently reporting iOS 26.4.2.

## Automated gate

1. Connect and unlock Buzz. Developer Mode must remain enabled.
2. Sign in under Xcode → Settings → Accounts so automatic provisioning can create
   profiles for the containing app, keyboard extension, and App Group.
3. Run:

   ```zsh
   zsh scripts/test-ios-device.sh
   ```

4. Retain the printed `.xcresult` path. The run must pass real Whisper model
   download/prewarm, Chinese transcription, speech-to-English translation,
   Rime full Pinyin, bridge recovery, performance, UI, signing, install, and launch.

## Manual keyboard and microphone gate

Record Pass/Fail and a short observation for every row.

| Test | Procedure | Expected result | Result |
|---|---|---|---|
| Keyboard setup | Enable Vibe Voice and Allow Full Access in Settings | Keyboard appears in the globe list | Pending |
| Chinese Pinyin | Type `nihao`, select the first intended candidate | Chinese candidates appear and commit correctly | Pending |
| English QWERTY | Switch to EN and type a sentence | Lowercase letters, space, delete and return work | Pending |
| Mode control | Long-press the microphone key | Original, Polish and Translate are selectable | Pending |
| Real recording | Request voice, switch to Vibe Voice, record the fixture sentence naturally | Level meter moves and local transcription completes | Pending |
| Result insertion | Return to the original text field | Exactly one result is inserted and marked consumed | Pending |
| Offline reuse | Enable Airplane Mode after the model is cached and repeat | Transcription works without network access | Pending |
| Background recovery | Background the app while idle and return | Model memory is released; recording can restart | Pending |
| Interruption | Interrupt recording with a call/audio-route change | App fails safely or resumes without duplicate text | Pending |
| Repeated use | Perform 20 short recordings in succession | No crash, runaway memory, or duplicate insertion | Pending |
| Thermal | Repeat transcription for 10 minutes | Thermal state is recorded; no critical shutdown | Pending |
| Privacy | Inspect network activity during cached transcription | Audio and transcript remain local | Pending |

## Acceptance evidence

- Device and OS:
- Git commit:
- `CFBundleVersion`:
- `.xcresult`:
- Cold model preparation time:
- Cached transcription/translation time:
- Peak resident memory:
- Thermal state before/after:
- Remaining defects:
- Final decision:

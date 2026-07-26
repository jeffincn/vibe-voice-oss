cask "vibe-voice-oss" do
  version "0.7.0"
  # Replaced by the release workflow with the checksum of the published zip.
  # A placeholder makes `brew install` fail loudly and print the real digest;
  # `:no_check` would have accepted whatever the URL happened to serve.
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/jeffincn/vibe-voice-oss/releases/download/v#{version}/VibeVoiceOSS-v#{version}.zip"
  name "Vibe Voice OSS"
  desc "Local-first voice input menu bar app with on-device ASR and LLM post-processing"
  homepage "https://github.com/jeffincn/vibe-voice-oss"

  depends_on macos: ">= :sequoia"
  depends_on arch: :arm64

  app "Vibe Voice OSS.app"

  zap trash: [
    "~/Documents/VibeVoiceOSS",
    "~/Library/Application Support/VibeVoiceOSS",
    "~/Library/Preferences/app.vibevoice.oss.macos.plist",
  ]

  caveats <<~EOS
    Vibe Voice OSS is not notarized by Apple. macOS will refuse to open it on
    first launch, and Homebrew has verified the download's SHA-256 against the
    checksum in this cask.

    To open it, right-click the app in /Applications and choose "Open", then
    confirm in the dialog. macOS remembers the choice.

    If macOS reports the app as damaged, the quarantine flag is stale. Remove it
    only after confirming the app came from the release above:

      shasum -a 256 "$(brew --cache)"/**/VibeVoiceOSS-v#{version}.zip
      xattr -d com.apple.quarantine "/Applications/Vibe Voice OSS.app"

    The app needs Microphone and Accessibility permissions on first launch.
  EOS
end

cask "vibe-voice-oss" do
  version "0.7.0"
  sha256 :no_check

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
    Vibe Voice OSS is not notarized by Apple yet. If macOS reports the app
    is damaged or can't be opened, install with:

      brew install --cask --no-quarantine vibe-voice-oss

    Or remove the quarantine attribute manually:

      xattr -cr "/Applications/Vibe Voice OSS.app"

    The app needs Microphone and Accessibility permissions on first launch.
  EOS
end

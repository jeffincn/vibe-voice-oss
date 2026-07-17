import type { VoiceState } from "./types";

declare global {
  interface Window {
    vibeVoiceSetState?: (state: VoiceState, level?: number) => void;
  }
}

export {};

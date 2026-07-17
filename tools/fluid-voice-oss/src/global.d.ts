import type { VoiceState } from "./types";

declare global {
  interface Window {
    vibeVoiceOSSSetState?: (state: VoiceState, level?: number) => void;
  }
}

export {};

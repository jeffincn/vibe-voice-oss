export type VoiceState = "idle" | "listening" | "speaking" | "processing";

export interface AudioBands {
  lowMid: number;
  mid: number;
  high: number;
  overall: number;
}

export const SILENT_BANDS: AudioBands = {
  lowMid: 0,
  mid: 0,
  high: 0,
  overall: 0,
};

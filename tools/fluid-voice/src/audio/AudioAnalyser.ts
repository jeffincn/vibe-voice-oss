import type { AudioBands } from "../types";
import { SILENT_BANDS } from "../types";

const clamp01 = (value: number) => Math.max(0, Math.min(1, value));

export class AudioAnalyser {
  private context?: AudioContext;
  private analyser?: AnalyserNode;
  private stream?: MediaStream;
  private bins?: Uint8Array<ArrayBuffer>;
  private smoothed: AudioBands = { ...SILENT_BANDS };

  async start(): Promise<void> {
    if (this.stream) return;
    this.stream = await navigator.mediaDevices.getUserMedia({
      audio: {
        autoGainControl: false,
        echoCancellation: true,
        noiseSuppression: true,
      },
    });
    this.context = new AudioContext();
    this.analyser = this.context.createAnalyser();
    this.analyser.fftSize = 1024;
    this.analyser.smoothingTimeConstant = 0;
    this.context.createMediaStreamSource(this.stream).connect(this.analyser);
    this.bins = new Uint8Array(this.analyser.frequencyBinCount);
  }

  sample(deltaTime: number): AudioBands {
    if (!this.analyser || !this.bins || !this.context) return this.smoothed;
    this.analyser.getByteFrequencyData(this.bins);

    const rawLowMid = this.bandEnergy(120, 650);
    const rawMid = this.bandEnergy(650, 2400);
    const rawHigh = this.bandEnergy(2400, 7200);
    const rawOverall = rawLowMid * 0.38 + rawMid * 0.44 + rawHigh * 0.18;

    this.smoothed = {
      lowMid: this.follow(this.smoothed.lowMid, rawLowMid, deltaTime),
      mid: this.follow(this.smoothed.mid, rawMid, deltaTime),
      high: this.follow(this.smoothed.high, rawHigh, deltaTime),
      overall: this.follow(this.smoothed.overall, rawOverall, deltaTime),
    };
    return this.smoothed;
  }

  stop(): void {
    this.stream?.getTracks().forEach((track) => track.stop());
    void this.context?.close();
    this.stream = undefined;
    this.context = undefined;
    this.analyser = undefined;
    this.bins = undefined;
    this.smoothed = { ...SILENT_BANDS };
  }

  private bandEnergy(lowHz: number, highHz: number): number {
    if (!this.bins || !this.context || !this.analyser) return 0;
    const hzPerBin = this.context.sampleRate / this.analyser.fftSize;
    const start = Math.max(1, Math.floor(lowHz / hzPerBin));
    const end = Math.min(this.bins.length, Math.ceil(highHz / hzPerBin));
    let sum = 0;
    for (let index = start; index < end; index += 1) {
      const normalized = this.bins[index] / 255;
      sum += normalized * normalized;
    }
    const rms = Math.sqrt(sum / Math.max(1, end - start));
    return clamp01((rms - 0.025) * 2.9);
  }

  private follow(current: number, target: number, deltaTime: number): number {
    const timeConstant = target > current ? 0.055 : 0.24;
    const coefficient = 1 - Math.exp(-deltaTime / timeConstant);
    return current + (target - current) * coefficient;
  }
}

import type { AudioBands, VoiceState } from "../types";
import { SILENT_BANDS } from "../types";

type RGB = readonly [number, number, number];

type FluidLayer = {
  seed: number;
  colorA: RGB;
  colorB: RGB;
  direction: number;
  slow: number;
  medium: number;
  fast: number;
  threshold: number;
};

const LAYERS: FluidLayer[] = [
  { seed: 11.7, colorA: [20, 235, 255], colorB: [20, 112, 255], direction: 1, slow: 0.019, medium: 0.067, fast: 0.151, threshold: 0.77 },
  { seed: 29.3, colorA: [42, 126, 255], colorB: [125, 67, 255], direction: -1, slow: 0.023, medium: 0.053, fast: 0.137, threshold: 0.82 },
  { seed: 47.9, colorA: [143, 57, 255], colorB: [231, 46, 255], direction: 1, slow: 0.017, medium: 0.079, fast: 0.173, threshold: 0.77 },
  { seed: 73.1, colorA: [255, 49, 166], colorB: [255, 76, 101], direction: -1, slow: 0.027, medium: 0.061, fast: 0.129, threshold: 0.76 },
  { seed: 101.9, colorA: [31, 255, 210], colorB: [15, 174, 255], direction: 1, slow: 0.021, medium: 0.071, fast: 0.163, threshold: 0.86 },
];

const ANCHORS = [
  [-0.58, -0.04, 0.2],
  [-0.29, 0.27, 0.36],
  [-0.13, -0.27, 0.4],
  [0.11, 0.08, 0.43],
  [0.3, -0.2, 0.35],
  [0.6, 0.16, 0.19],
] as const;

const STATE_ENERGY: Record<VoiceState, number> = {
  idle: 0.34,
  listening: 0.56,
  speaking: 0.78,
  processing: 0.67,
};

const STATE_SPEED: Record<VoiceState, number> = {
  idle: 0.5,
  listening: 0.76,
  speaking: 1,
  processing: 1.27,
};

const clamp01 = (value: number) => Math.max(0, Math.min(1, value));
const smoothstep = (edge0: number, edge1: number, value: number) => {
  const x = clamp01((value - edge0) / (edge1 - edge0));
  return x * x * (3 - 2 * x);
};
const mix = (a: number, b: number, amount: number) => a + (b - a) * amount;
const fade = (value: number) => value * value * (3 - 2 * value);

export class OrganicVoiceRenderer {
  private readonly context: CanvasRenderingContext2D;
  private readonly fieldCanvas = document.createElement("canvas");
  private readonly fieldContext: CanvasRenderingContext2D;
  private readonly bloomCanvas = document.createElement("canvas");
  private readonly bloomContext: CanvasRenderingContext2D;
  private imageData = new ImageData(1, 1);
  private frameRequest = 0;
  private previousTime = 0;
  private elapsed = 0;
  private width = 1;
  private height = 1;
  private dpr = 1;
  private state: VoiceState = "idle";
  private audio: AudioBands = { ...SILENT_BANDS };
  private displayedEnergy = STATE_ENERGY.idle;
  private displayedSpeed = STATE_SPEED.idle;
  private sampleAudio?: (deltaTime: number) => AudioBands;
  private reduceMotion = false;

  constructor(private readonly canvas: HTMLCanvasElement) {
    const context = canvas.getContext("2d", { alpha: true });
    const fieldContext = this.fieldCanvas.getContext("2d", { alpha: true });
    const bloomContext = this.bloomCanvas.getContext("2d", { alpha: true });
    if (!context || !fieldContext || !bloomContext) throw new Error("Canvas 2D is unavailable.");
    this.context = context;
    this.fieldContext = fieldContext;
    this.bloomContext = bloomContext;
    this.reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  }

  setState(state: VoiceState): void {
    this.state = state;
  }

  setAudioSampler(sampler?: (deltaTime: number) => AudioBands): void {
    this.sampleAudio = sampler;
  }

  setAudioBands(bands: AudioBands): void {
    this.audio = bands;
  }

  resize(cssWidth: number, cssHeight: number): void {
    this.width = Math.max(1, cssWidth);
    this.height = Math.max(1, cssHeight);
    this.dpr = Math.min(2, window.devicePixelRatio || 1);
    this.canvas.width = Math.round(this.width * this.dpr);
    this.canvas.height = Math.round(this.height * this.dpr);
    this.bloomCanvas.width = this.canvas.width;
    this.bloomCanvas.height = this.canvas.height;

    const fieldScale = Math.min(1, 460 / this.width);
    this.fieldCanvas.width = Math.max(80, Math.round(this.width * fieldScale));
    this.fieldCanvas.height = Math.max(44, Math.round(this.height * fieldScale));
    this.imageData = this.fieldContext.createImageData(this.fieldCanvas.width, this.fieldCanvas.height);
  }

  start(): void {
    if (this.frameRequest) return;
    this.previousTime = performance.now();
    this.frameRequest = requestAnimationFrame(this.render);
  }

  stop(): void {
    cancelAnimationFrame(this.frameRequest);
    this.frameRequest = 0;
  }

  private render = (now: number): void => {
    const deltaTime = Math.min(0.05, Math.max(0.001, (now - this.previousTime) / 1000));
    this.previousTime = now;
    if (!this.reduceMotion) this.elapsed += deltaTime;
    if (this.sampleAudio) this.audio = this.sampleAudio(deltaTime);

    const audioEnergy = this.state === "speaking" ? this.audio.overall * 0.46 : 0;
    const targetEnergy = clamp01(STATE_ENERGY[this.state] + audioEnergy);
    const targetSpeed = STATE_SPEED[this.state] + (this.state === "speaking" ? this.audio.high * 0.34 : 0);
    this.displayedEnergy = this.follow(this.displayedEnergy, targetEnergy, deltaTime, 0.08, 0.31);
    this.displayedSpeed = this.follow(this.displayedSpeed, targetSpeed, deltaTime, 0.14, 0.37);

    this.paintField(this.elapsed * this.displayedSpeed);
    this.composite();
    this.frameRequest = requestAnimationFrame(this.render);
  };

  private paintField(time: number): void {
    const width = this.fieldCanvas.width;
    const height = this.fieldCanvas.height;
    const data = this.imageData.data;
    const aspect = width / height;
    const verticalScale = Math.min(1, Math.max(0.72, (height / width) / 0.38));
    const low = this.state === "speaking" ? this.audio.lowMid : 0;
    const mid = this.state === "speaking" ? this.audio.mid : 0;
    const high = this.state === "speaking" ? this.audio.high : 0;
    const balls = LAYERS.map((layer, layerIndex) =>
      ANCHORS.map(([anchorX, anchorY, baseRadius], ballIndex) => {
        const seed = layer.seed + ballIndex * 17.31;
        const slowT = time * layer.slow * layer.direction;
        const mediumT = time * layer.medium * -layer.direction;
        const fastT = time * layer.fast;
        const flowX = this.fbm(seed, slowT, layerIndex * 0.71, 3) * 0.13;
        const flowY = this.fbm(seed * 0.23, mediumT, ballIndex * 0.91, 3) * 0.16;
        const localX = this.fbm(seed + 4.7, fastT, anchorY, 2) * 0.035;
        const localY = this.fbm(seed + 9.1, -fastT, anchorX, 2) * 0.04;
        const breathe = 1 + this.fbm(seed + 13.3, mediumT * 0.77, slowT, 2) * 0.22;
        const stretch = this.fbm(seed + 23.9, mediumT, fastT * 0.21, 2);
        const angleNoise = this.fbm(seed + 31.7, slowT, mediumT, 2);
        return {
          x: anchorX + flowX + localX + [-0.07, 0.05, -0.02, 0.08, -0.04][layerIndex],
          y: (anchorY * (layerIndex % 2 === 0 ? 0.84 : -0.78)
            + flowY + localY + [0.05, -0.08, 0.1, -0.04, 0.01][layerIndex]) * verticalScale,
          rx: baseRadius * breathe * (1.04 + stretch * 0.24 + low * 0.22),
          ry: baseRadius * breathe * (0.72 - stretch * 0.16 + mid * 0.18) * verticalScale,
          cosine: Math.cos(angleNoise * 1.9 + layerIndex * 0.43),
          sine: Math.sin(angleNoise * 1.9 + layerIndex * 0.43),
          weight: 0.72 + this.noise3(seed, mediumT, 7.3) * 0.16,
        };
      }),
    );

    for (let py = 0; py < height; py += 1) {
      const y = (py / (height - 1) * 2 - 1) * 0.92;
      for (let px = 0; px < width; px += 1) {
        const x = (px / (width - 1) * 2 - 1) * aspect * 0.39;
        const envelope = Math.exp(-Math.pow(Math.abs(x) / (aspect * 0.34), 4))
          * Math.exp(-Math.pow(Math.abs(y) / 0.82, 4));
        let red = 0;
        let green = 0;
        let blue = 0;
        let alpha = 0;

        LAYERS.forEach((layer, layerIndex) => {
          let field = 0;
          for (const ball of balls[layerIndex]) {
            const dx = x - ball.x;
            const dy = y - ball.y;
            const localX = dx * ball.cosine + dy * ball.sine;
            const localY = -dx * ball.sine + dy * ball.cosine;
            const distance = localX * localX / (ball.rx * ball.rx)
              + localY * localY / (ball.ry * ball.ry);
            field += ball.weight * Math.exp(-distance * (1.62 + high * 0.18));
          }

          const threshold = layer.threshold - this.displayedEnergy * 0.15;
          const density = smoothstep(threshold, threshold + 0.34, field) * envelope;
          if (density < 0.003) return;
          const colorFlow = clamp01(0.5
            + this.noise3(x * 0.72 + layer.seed, y * 0.88, time * layer.medium) * 0.43);
          const layerAlpha = density * (0.14 + this.displayedEnergy * 0.14);
          const layerRed = mix(layer.colorA[0], layer.colorB[0], colorFlow) / 255;
          const layerGreen = mix(layer.colorA[1], layer.colorB[1], colorFlow) / 255;
          const layerBlue = mix(layer.colorA[2], layer.colorB[2], colorFlow) / 255;
          red = 1 - (1 - red) * (1 - layerRed * layerAlpha);
          green = 1 - (1 - green) * (1 - layerGreen * layerAlpha);
          blue = 1 - (1 - blue) * (1 - layerBlue * layerAlpha);
          alpha = 1 - (1 - alpha) * (1 - layerAlpha);
        });

        const highlight = smoothstep(0.68, 0.98, alpha) * envelope * (0.035 + this.displayedEnergy * 0.055);
        red = clamp01(red + highlight * 0.78);
        green = clamp01(green + highlight * 0.91);
        blue = clamp01(blue + highlight);
        const offset = (py * width + px) * 4;
        const unpremultiply = alpha > 0.001 ? 1 / alpha : 0;
        data[offset] = clamp01(red * unpremultiply) * 255;
        data[offset + 1] = clamp01(green * unpremultiply) * 255;
        data[offset + 2] = clamp01(blue * unpremultiply) * 255;
        data[offset + 3] = clamp01(alpha * 1.5) * 255;
      }
    }
    this.fieldContext.putImageData(this.imageData, 0, 0);
  }

  private composite(): void {
    const pixelWidth = this.canvas.width;
    const pixelHeight = this.canvas.height;
    this.context.setTransform(1, 0, 0, 1, 0, 0);
    this.context.clearRect(0, 0, pixelWidth, pixelHeight);
    this.bloomContext.setTransform(1, 0, 0, 1, 0, 0);
    this.bloomContext.clearRect(0, 0, pixelWidth, pixelHeight);

    this.bloomContext.globalCompositeOperation = "screen";
    this.bloomContext.filter = `blur(${(11 + this.displayedEnergy * 7) * this.dpr}px)`;
    this.bloomContext.globalAlpha = 0.34;
    this.bloomContext.drawImage(this.fieldCanvas, 0, 0, pixelWidth, pixelHeight);

    this.context.globalCompositeOperation = "screen";
    this.context.globalAlpha = 0.5;
    this.context.drawImage(this.bloomCanvas, 0, 0);
    this.context.globalCompositeOperation = "source-over";
    this.context.filter = `blur(${(0.85 + this.displayedEnergy * 0.7) * this.dpr}px)`;
    this.context.globalAlpha = 0.96;
    this.context.drawImage(this.fieldCanvas, 0, 0, pixelWidth, pixelHeight);
    this.context.globalCompositeOperation = "screen";
    this.context.filter = "none";
    this.context.globalAlpha = 0.11;
    this.context.drawImage(this.fieldCanvas, 0, 0, pixelWidth, pixelHeight);
    this.context.filter = "none";
    this.context.globalAlpha = 1;
  }

  private fbm(x: number, y: number, z: number, octaves: number): number {
    let result = 0;
    let amplitude = 0.58;
    let frequency = 1;
    let normalization = 0;
    for (let octave = 0; octave < octaves; octave += 1) {
      result += this.noise3(x * frequency, y * frequency, z * frequency) * amplitude;
      normalization += amplitude;
      amplitude *= 0.47;
      frequency *= 2.03;
    }
    return result / normalization;
  }

  private noise3(x: number, y: number, z: number): number {
    const xi = Math.floor(x);
    const yi = Math.floor(y);
    const zi = Math.floor(z);
    const tx = fade(x - xi);
    const ty = fade(y - yi);
    const tz = fade(z - zi);
    const a = mix(this.hash(xi, yi, zi), this.hash(xi + 1, yi, zi), tx);
    const b = mix(this.hash(xi, yi + 1, zi), this.hash(xi + 1, yi + 1, zi), tx);
    const c = mix(this.hash(xi, yi, zi + 1), this.hash(xi + 1, yi, zi + 1), tx);
    const d = mix(this.hash(xi, yi + 1, zi + 1), this.hash(xi + 1, yi + 1, zi + 1), tx);
    return mix(mix(a, b, ty), mix(c, d, ty), tz) * 2 - 1;
  }

  private hash(x: number, y: number, z: number): number {
    const value = Math.sin(x * 127.1 + y * 311.7 + z * 74.7) * 43758.5453123;
    return value - Math.floor(value);
  }

  private follow(current: number, target: number, dt: number, attack: number, release: number): number {
    const timeConstant = target > current ? attack : release;
    return current + (target - current) * (1 - Math.exp(-dt / timeConstant));
  }
}

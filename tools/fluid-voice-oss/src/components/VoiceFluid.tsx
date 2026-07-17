import { useEffect, useRef } from "react";
import { AudioAnalyser } from "../audio/AudioAnalyser";
import type { VoiceState } from "../types";
import { OrganicVoiceRenderer } from "../visual/OrganicVoiceRenderer";

type VoiceFluidProps = {
  state: VoiceState;
  microphone?: boolean;
  className?: string;
};

export function VoiceFluid({ state, microphone = false, className }: VoiceFluidProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const rendererRef = useRef<OrganicVoiceRenderer | null>(null);
  const analyserRef = useRef<AudioAnalyser | null>(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const renderer = new OrganicVoiceRenderer(canvas);
    rendererRef.current = renderer;
    const observer = new ResizeObserver(([entry]) => {
      renderer.resize(entry.contentRect.width, entry.contentRect.height);
    });
    observer.observe(canvas);
    renderer.start();
    return () => {
      observer.disconnect();
      renderer.stop();
      rendererRef.current = null;
    };
  }, []);

  useEffect(() => {
    rendererRef.current?.setState(state);
  }, [state]);

  useEffect(() => {
    const receiveAudio = (event: Event) => {
      rendererRef.current?.setAudioBands((event as CustomEvent<{
        lowMid: number;
        mid: number;
        high: number;
        overall: number;
      }>).detail);
    };
    window.addEventListener("vibevoice-oss-audio", receiveAudio);
    return () => window.removeEventListener("vibevoice-oss-audio", receiveAudio);
  }, []);

  useEffect(() => {
    let cancelled = false;
    if (microphone) {
      const analyser = new AudioAnalyser();
      analyserRef.current = analyser;
      void analyser.start().then(() => {
        if (cancelled) return analyser.stop();
        rendererRef.current?.setAudioSampler((deltaTime) => analyser.sample(deltaTime));
      }).catch(() => {
        analyser.stop();
      });
    }
    return () => {
      cancelled = true;
      rendererRef.current?.setAudioSampler(undefined);
      analyserRef.current?.stop();
      analyserRef.current = null;
    };
  }, [microphone]);

  return (
    <canvas
      ref={canvasRef}
      className={className}
      role="img"
      aria-label={`Voice visualization: ${state}`}
    />
  );
}

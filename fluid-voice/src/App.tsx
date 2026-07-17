import { useEffect, useState } from "react";
import { VoiceFluid } from "./components/VoiceFluid";
import type { VoiceState } from "./types";

const states: VoiceState[] = ["idle", "listening", "speaking", "processing"];

export default function App() {
  const [state, setState] = useState<VoiceState>("speaking");
  const [microphone, setMicrophone] = useState(false);
  const embedded = new URLSearchParams(window.location.search).has("embed")
    || document.documentElement.classList.contains("native-embed");

  useEffect(() => {
    window.vibeVoiceSetState = (nextState, level = 0) => {
      setState(nextState);
      const energy = Math.max(0, Math.min(1, level));
      window.dispatchEvent(new CustomEvent("vibevoice-audio", {
        detail: {
          lowMid: energy * 0.88,
          mid: energy,
          high: energy * 0.64,
          overall: energy,
        },
      }));
    };
    return () => { delete window.vibeVoiceSetState; };
  }, []);

  return (
    <main className={embedded ? "embedded" : ""}>
      <section className="stage" aria-label="Siri style fluid animation preview">
        <VoiceFluid state={state} microphone={microphone} className="voice-fluid" />
      </section>
      {!embedded && <nav className="controls" aria-label="Animation states">
        {states.map((value) => (
          <button key={value} className={state === value ? "active" : ""} onClick={() => setState(value)}>
            {value}
          </button>
        ))}
        <button className={microphone ? "active" : ""} onClick={() => setMicrophone((value) => !value)}>
          {microphone ? "mic on" : "use mic"}
        </button>
      </nav>}
    </main>
  );
}

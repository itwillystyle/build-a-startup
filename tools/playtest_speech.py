"""playtest_speech.py -- what he said while recording, with the video's clock.

Called by `lune run tools/bas playtest prep`. Prints one line per phrase:
    [0:12] there's no pad to take the worker to
and nothing when the recording has no speech (game sound only).

Uses faster-whisper's small.en model on the CPU (already in the Hugging Face
cache on this machine). Usage: python tools/playtest_speech.py <video>
"""
import sys


def clock(t):
    t = int(round(t))
    return f"{t // 60}:{t % 60:02d}"


def main():
    if len(sys.argv) != 2:
        print("usage: python tools/playtest_speech.py <video>", file=sys.stderr)
        return 2
    from faster_whisper import WhisperModel

    model = WhisperModel("small.en", device="cpu", compute_type="int8")
    # vad_filter: skip music and game sound, so silence does not become made-up words
    segments, _ = model.transcribe(sys.argv[1], language="en", vad_filter=True, beam_size=5)
    for s in segments:
        text = s.text.strip()
        # whisper's habit on noise: a lone "you" / "Thank you." with no speech under it
        if text and s.no_speech_prob < 0.6:
            print(f"[{clock(s.start)}] {text}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

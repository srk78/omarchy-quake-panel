#!/usr/bin/env python3
"""
wakeword.py — spots "Hey Foxy" on the panel's own mic, then exits.

Deliberately does ONE job and stops: paBridge.js runs this only while the mic isn't
needed for anything else, and kills it (or lets it exit itself, right here) the moment
a wake word fires — Voxtype's own `record start` needs exclusive-enough access to the
same device right after, and never running both at once sidesteps any question of
whether this machine's ALSA config actually shares capture across processes (dsnoop)
or not. paBridge.js is responsible for relaunching this script once a full turn
finishes, if continuous mode is still on.

stdout: one JSON object per line —
  {"event": "ready"}          — listening has actually started
  {"event": "wake", "score": 0.87}
  {"event": "error", "message": "..."}

MIT-licensed: pure orchestration glue, no device protocol, no model weights of its own.
The bundled model (models/hey_foxy.onnx) was trained via nanowakeword's own Colab
notebook (github.com/arcosoph/nanowakeword) — see HISTORY.md for why that tool, not
openWakeWord's own training notebook, ended up producing it, and its own Apache-2.0
license for the training code/library this model was made with.
"""
import json
import os
import sys
import time

import numpy as np
import sounddevice as sd
from nanowakeword import NanoInterpreter

# A one-of-a-kind trained artifact (nobody else could regenerate it without redoing the
# whole training process), unlike Piper's voice model — so it's committed to the repo
# rather than kept as an external download, colocated with this script. Still
# env-overridable so swapping in a different trained phrase is a config change, not a
# code edit — same pattern as paBridge.js's PIPER_MODEL/OQP_PA_SPEAKER_SINK.
MODEL_PATH = os.environ.get(
    "OQP_PA_WAKEWORD_MODEL",
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "models", "hey_foxy.onnx"),
)
THRESHOLD = float(os.environ.get("OQP_PA_WAKEWORD_THRESHOLD", "0.5"))
SAMPLE_RATE = 16000
FRAME_SAMPLES = 1280  # 80ms at 16kHz — nanowakeword's own expected frame size (matches openWakeWord's)
# Matched by substring, not exact name or PortAudio index — same philosophy as
# ops/voxtype/pa.example.toml pinning the mic by its stable ALSA card name rather than
# an index that can shift. This is the panel's separate USB audio codec (see
# HISTORY.md §22), not the laptop's own built-in mic.
DEVICE_NAME_MATCH = "USB PnP Audio Device"


def out(obj):
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()


def find_device():
    for index, info in enumerate(sd.query_devices()):
        if info.get("max_input_channels", 0) > 0 and DEVICE_NAME_MATCH in info.get("name", ""):
            return index
    return None


# ALSA doesn't always make a device available to the next opener the instant a prior
# process releases it — confirmed live: restarting this script right after Voxtype (or
# a previous instance of this same script) had just used the same device intermittently
# raised "Invalid sample rate [PaErrorCode -9997]", a transient PortAudio probe failure,
# not a real configuration problem (the exact same open() call succeeds a moment later).
# paBridge.js already waits a bit before relaunching this script for the same reason;
# this retry is the second line of defense in case that gap isn't quite enough.
def open_stream(device):
    attempts = 5
    delay_s = 0.3
    last_error = None
    for _ in range(attempts):
        try:
            return sd.InputStream(device=device, samplerate=SAMPLE_RATE, channels=1, dtype="int16")
        except sd.PortAudioError as e:
            last_error = e
            time.sleep(delay_s)
    raise last_error


def main():
    device = find_device()
    if device is None:
        out({"event": "error", "message": f"no input device matching '{DEVICE_NAME_MATCH}'"})
        sys.exit(1)

    # Fully local, single-model mode (no cascade/gate, no remote verifier) — this
    # machine is an ordinary laptop-class CPU, not the low-power edge device the
    # cascade/remote-verifier modes exist for; a plain single model is nanowakeword's
    # own recommended shape for "common use" (see its README's deployment modes table).
    interpreter = NanoInterpreter.load_model(MODEL_PATH)

    with open_stream(device) as stream:
        out({"event": "ready"})
        while True:
            chunk, _overflowed = stream.read(FRAME_SAMPLES)
            frame = chunk.reshape(-1)
            result = interpreter.predict(frame)
            score = result.score
            if score >= THRESHOLD:
                out({"event": "wake", "score": float(score)})
                return


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
    except Exception as e:  # noqa: BLE001 — this is a leaf process; report and exit, don't traceback-spam the parent's stderr
        out({"event": "error", "message": str(e)})
        sys.exit(1)

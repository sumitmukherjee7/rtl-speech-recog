import numpy as np
import librosa

INPUT_WAV = "input.wav"          # your WAV file in the same folder
OUTPUT_TXT = "audio_samples.txt" # output samples for Verilog

# --- Load WAV ---
print("Loading WAV...")
audio, sr = librosa.load(INPUT_WAV, sr=None, mono=True)

print(f"Loaded {INPUT_WAV}")
print(f"Sample rate: {sr}")
print(f"Total samples: {len(audio)}")

# --- Convert to 16-bit PCM ---
audio_int16 = (audio * 32767).astype(np.int16)

# --- Save to text file ---
np.savetxt(OUTPUT_TXT, audio_int16, fmt="%d")
print(f"Saved 16-bit PCM samples to {OUTPUT_TXT}")

print("Done.")

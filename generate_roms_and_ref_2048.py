# python/generate_roms_and_ref_2048.py
# Generates ROM hex files for N=2048, hop=512, n_mels=40, n_mfcc=13
# Also writes reference MFCCs (32 x 13) computed using librosa with same params.
#
# Usage: python generate_roms_and_ref_2048.py
# Requires: numpy, scipy, librosa

import numpy as np
import os
import math
from scipy.fftpack import dct as scidct
import librosa

# output dir relative to this script
out_dir = os.path.join(os.path.dirname(__file__), '..', 'roms')
os.makedirs(out_dir, exist_ok=True)

# Parameters to match compute_mfcc()
SAMPLE_RATE = 16000
N = 2048
HOP_LENGTH = 512
MEL_BANDS = 40
MFCC_COEFFS = 13
TARGET_TIME_STEPS = 32  # expected number of frames for 1s clip

# helper to convert signed int to hex string
def to_hex_signed(val, bits):
    if val < 0:
        val = (1<<bits) + val
    return format(val & ((1<<bits)-1), '04x') if bits==16 else format(val & ((1<<bits)-1), '08x')

# 1) Hamming window (librosa uses default 'hann' for many, but your compute_mfcc likely used default 'hamming' earlier? 
# compute_mfcc() didn't specify window type; librosa.feature.mfcc uses the STFT window default (hann). To be safe, we will use the 'hann' window (librosa.stft default).
# If your compute_mfcc used a different window, change this accordingly.)
window = np.hanning(N)   # use hann to match librosa.stft default
# Quantize to Q1.15
window_q = np.round(window * (1<<15)).astype(np.int16)
with open(os.path.join(out_dir, 'window.hex'), 'w') as f:
    for v in window_q:
        f.write(to_hex_signed(int(v), 16) + '\n')
print("Wrote window.hex (hann, Q1.15)")

# 2) Twiddle factors: not required if using vendor FFT IP. We still create a twiddle file in case iterative FFT is used.
twiddles = []
for k in range(N//2):
    angle = -2.0 * np.pi * k / N
    c = int(round(np.cos(angle) * (1<<31)))
    s = int(round(np.sin(angle) * (1<<31)))
    twiddles.append((c, s))
with open(os.path.join(out_dir, 'twiddle.hex'), 'w') as f:
    for c,s in twiddles:
        f.write(format(c & 0xffffffff, '08x') + format(s & 0xffffffff, '08x') + '\n')
print("Wrote twiddle.hex (Q1.31 pairs)")

# 3) Mel filterbank using librosa (n_fft=N)
mel = librosa.filters.mel(sr=SAMPLE_RATE, n_fft=N, n_mels=MEL_BANDS, fmin=0.0, fmax=SAMPLE_RATE/2.0)
# librosa returns mel matrix shape (n_mels, 1 + N/2). We only need first N/2+1 bins.
fft_bins = N//2 + 1
mel_w = mel[:, :fft_bins]   # shape (40, 1025)

# Quantize mel weights to Q1.15 (weights between 0 and ~1)
mel_q = np.round(mel_w * (1<<15)).astype(np.int16)
with open(os.path.join(out_dir, 'mel_weights.hex'), 'w') as f:
    # store as MEL_BANDS blocks each with fft_bins entries
    for i in range(MEL_BANDS):
        for j in range(fft_bins):
            f.write(to_hex_signed(int(mel_q[i,j]), 16) + '\n')
print("Wrote mel_weights.hex (40 x {:d}, Q1.15)".format(fft_bins))

# 4) DCT matrix (MFCC_COEFFS x MEL_BANDS) - use same DCT-II (librosa uses scipy's dct with norm='ortho' sometimes)
# We'll use orthonormal DCT as in librosa.feature.mfcc uses dct type=2 with norm='ortho' internally.
# However MFCC typically does not use the 'ortho' normalization for hardware - to match librosa we compute dct basis and let Python compute reference
dct_w = np.zeros((MFCC_COEFFS, MEL_BANDS))
for n in range(MFCC_COEFFS):
    for i in range(MEL_BANDS):
        dct_w[n,i] = math.cos(math.pi * n * (i + 0.5) / MEL_BANDS)
# Quantize to Q1.15
dct_q = np.round(dct_w * (1<<15)).astype(np.int16)
with open(os.path.join(out_dir, 'dct.hex'), 'w') as f:
    for n in range(MFCC_COEFFS):
        for i in range(MEL_BANDS):
            f.write(to_hex_signed(int(dct_q[n,i]), 16) + '\n')
print("Wrote dct.hex (13 x 40, Q1.15)")

# 5) Log LUT: we'll build a LUT for natural log (librosa uses log amplitude; MFCC uses log of mel energies)
# We'll create a LUT mapping input in range [1 .. 2^24] to ln(value) scaled to Q6.10.
lut_bits = 12
lut_size = 1<<lut_bits
max_in = (1<<24)-1
xs = np.linspace(1, max_in, lut_size)
logs = np.log(xs + 1e-12)
logs_q = np.round(logs * (1<<10)).astype(np.int16)  # Q6.10
with open(os.path.join(out_dir, 'log_lut.hex'), 'w') as f:
    for val in logs_q:
        f.write(to_hex_signed(int(val), 16) + '\n')
print("Wrote log_lut.hex (LUT size {})".format(lut_size))

# 6) Create sample 1-second frame (sine + noise) for test frame and compute reference MFCCs (librosa)
t = np.arange(0, 1.0, 1.0/SAMPLE_RATE)[:SAMPLE_RATE]
freq = 440.0
frame = 0.6 * np.sin(2*np.pi*freq*t) + 0.02*np.random.randn(len(t))
frame_int = np.round(frame * (1<<15)).astype(np.int16)
with open(os.path.join(out_dir, 'frame.hex'), 'w') as f:
    for v in frame_int:
        f.write(to_hex_signed(int(v), 16) + '\n')
print("Wrote frame.hex (1s test frame)")

# 7) compute MFCC reference using same parameters as your compute_mfcc
mfccs = librosa.feature.mfcc(y=frame.astype(np.float32),
                             sr=SAMPLE_RATE,
                             n_mfcc=MFCC_COEFFS,
                             n_fft=N,
                             hop_length=HOP_LENGTH,
                             n_mels=MEL_BANDS)
# mfccs shape: (13, time_frames)
mfccs_T = mfccs.T  # (time_frames, 13)
# ensure TARGET_TIME_STEPS frames (should be 32 for 1s clip)
if mfccs_T.shape[0] < TARGET_TIME_STEPS:
    pad = TARGET_TIME_STEPS - mfccs_T.shape[0]
    mfccs_T = np.pad(mfccs_T, ((0,pad),(0,0)), mode='constant')
elif mfccs_T.shape[0] > TARGET_TIME_STEPS:
    mfccs_T = mfccs_T[:TARGET_TIME_STEPS,:]

# quantize reference MFCCs to Q6.10 (for hardware comparison)
mfcc_q = np.round(mfccs_T * (1<<10)).astype(np.int16)
with open(os.path.join(out_dir, 'ref_mfcc.txt'), 'w') as f:
    for row in mfcc_q:
        f.write(' '.join(map(str,row.tolist())) + '\n')
print("Wrote ref_mfcc.txt ({} x {}, Q6.10)".format(*mfcc_q.shape))

print("All ROMs and reference MFCC generated in:", out_dir)

import numpy as np

# Load decimal PCM samples
data = np.loadtxt("audio_samples.txt", dtype=np.int16)

# Convert to unsigned 16-bit
data_u16 = data.astype(np.uint16)

with open("audio_samples.hex", "w") as f:
    for v in data_u16:
        f.write("{:04x}\n".format(v))

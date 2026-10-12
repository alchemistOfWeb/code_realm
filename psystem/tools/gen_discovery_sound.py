# Синтез звука «открыта новая местность» (в духе Skyrim): глухой удар литавр, нарастающий
# низкий аккорд струнных/меди ре минор, высокий «хор» и длинная реверберация.
# Запуск из папки psystem: python tools/gen_discovery_sound.py  → assets/audio/jingles/discovery.wav
import os
import wave

import numpy as np

SR = 44100
DUR = 5.0
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "audio", "jingles", "discovery.wav")
rng = np.random.default_rng(7)
t = np.arange(int(SR * DUR)) / SR


def env(attack, hold, release, total=DUR, curve=2.0):
    e = np.zeros_like(t)
    a = t < attack
    e[a] = (t[a] / attack) ** curve
    h = (t >= attack) & (t < attack + hold)
    e[h] = 1.0
    r = t >= attack + hold
    e[r] = np.exp(-(t[r] - attack - hold) / (release / 4.0))
    return e


def saw(freq, detune_cents=0.0, phase=0.0):
    f = freq * 2 ** (detune_cents / 1200.0)
    ph = (f * t + phase) % 1.0
    return 2.0 * ph - 1.0


def lowpass(x, cutoff):
    # Однополюсный ФНЧ с меняющейся частотой среза (cutoff — массив Гц)
    y = np.zeros_like(x)
    a = 1.0 - np.exp(-2 * np.pi * cutoff / SR)
    acc = 0.0
    for i in range(len(x)):
        acc += a[i] * (x[i] - acc)
        y[i] = acc
    return y


def reverb(x, seconds=3.2, mix=0.42):
    n = int(SR * seconds)
    tt = np.arange(n) / SR
    ir = rng.standard_normal(n) * np.exp(-tt / (seconds / 6.0))
    ir[: int(SR * 0.012)] = 0.0
    ir /= np.sqrt(np.sum(ir ** 2))
    size = 1 << int(np.ceil(np.log2(len(x) + n)))
    wet = np.fft.irfft(np.fft.rfft(x, size) * np.fft.rfft(ir, size), size)[: len(x)]
    return x * (1 - mix) + wet * mix * 2.2


# --- Литавры / удар: синус с падающей частотой + шумовой «удар» мягкого молотка
drop = 62.0 * np.exp(-t * 3.0) + 40.0
boom = np.sin(2 * np.pi * np.cumsum(drop) / SR) * np.exp(-t / 0.9)
thump = lowpass(rng.standard_normal(len(t)) * np.exp(-t / 0.06), np.full_like(t, 900.0))
drum = boom * 0.9 + thump * 0.5

# --- Низкий аккорд (струнные + медь): ре минор, нарастание и раскрытие фильтра
chord = [73.42, 110.0, 146.83, 174.61, 220.0, 293.66]
pad = np.zeros_like(t)
for i, f in enumerate(chord):
    for d in (-7.0, 0.0, 6.0):
        pad += saw(f, d, rng.random()) * (1.0 if i < 3 else 0.7)
cut = 350.0 + 1500.0 * np.clip(t / 1.4, 0, 1) ** 1.5 * np.exp(-np.clip(t - 2.6, 0, None) / 1.5)
pad = lowpass(pad, cut) * env(1.1, 1.6, 2.2) * 0.22

# --- «Хор»: мягкие синусы с вибрато (ля, ре, фа второй октавы), вступают чуть позже
choir = np.zeros_like(t)
vib = 1.0 + 0.004 * np.sin(2 * np.pi * 5.2 * t)
for f, g in ((440.0, 0.5), (587.33, 0.45), (698.46, 0.35), (880.0, 0.2)):
    ph = np.cumsum(f * vib) / SR
    choir += g * (np.sin(2 * np.pi * ph) + 0.3 * np.sin(4 * np.pi * ph))
delay = (t > 0.35).astype(float)
choir *= env(1.6, 1.2, 2.4) * delay * 0.12

mix = drum * 0.75 + pad + choir
mix = reverb(mix)
fade = np.ones_like(t)
fade[-int(SR * 0.6):] = np.linspace(1, 0, int(SR * 0.6))
mix *= fade
mix /= np.max(np.abs(mix)) / 0.85

# Стерео: лёгкая разница каналов за счёт задержки хора
left = mix
right = np.concatenate([np.zeros(int(SR * 0.009)), mix[: -int(SR * 0.009)]]) * 0.6 + mix * 0.4
stereo = np.stack([left, right], axis=1)
pcm = (np.clip(stereo, -1, 1) * 32767).astype(np.int16)
with wave.open(OUT, "wb") as w:
    w.setnchannels(2)
    w.setsampwidth(2)
    w.setframerate(SR)
    w.writeframes(pcm.tobytes())
print("written", OUT, pcm.shape)

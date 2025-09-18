# aKMServer

_Realtime Spatial Audio Panning Server made with SuperCollider_

[![License Badge](https://img.shields.io/badge/GNU_GPLv3-blue.svg?style=plastic&logo=gnu&label=license)](https://www.gnu.org/licenses/gpl-3.0.en.html)

Pre-release prototype.

---

## Table of Contents

- [Overview / Presentation](#overview)
- [Installation](#installation)
- [Usage](#usage)
- [How it Works](#how-it-works)
- [Panning Algorithm](#panning-algorithm)
- [OSC API](#osc-api)
- [Credits and Support](#credits-and-support)
- [License](#license)
- [Notes](#notes)

## Overview

aKMServer (file: `akM_spatServer.scd`) is the real‑time spatial audio panning engine of the aKM software system. It receives multi‑channel audio inputs (virtual “sources”), computes per‑speaker gains and time‑of‑flight delays using a custom radius‑limited inverse‑distance power law (kNN‑style) panning, and renders to a multi‑speaker array (satellites + subs). The server includes system gain, per‑speaker gains, multichannel reverb, per‑band filters, and per‑speaker parametric EQ.

Primary control is via OSC and designed to be driven by the companion controller and visualizer application [aKMControl](https://github.com/contactlaplanque/akm-control), which handles boot, runtime control, and shutdown orchestration.

Current defaults in this prototype:

- Inputs (sources): 32 (_Tested up to 64_)
- Outputs: 12 satellites + 2 subs (14 total) (_Tested up to 64_)
- Sample rate: 48 kHz
- OSC listen port: `23446`; ACK/heartbeat target: `127.0.0.1:23444`

## Installation

### Dependencies

- [SuperCollider](https://supercollider.github.io/) (SC) 3.12+ (required)
- SC3-plugins 3.13.0+ (required)
  - Releases: [HERE](`https://github.com/supercollider/sc3-plugins/releases`)
- An audio driver capable of exposing sufficient input/output channels
  - macOS: CoreAudio (audio I/O via JACK Router or Blackhole)
  - Windows: ASIO (audio I/O via JACK Router or VB-Audio-Matrix)
  - Linux: JACK (audio I/O via JACK Router)

### macOS

1. Install SuperCollider and SC3-plugins (see link above).
2. Ensure your audio interface exposes at least the required input/output channels.
3. Optional: Install JACK if you plan to use `JackRouter`.

### Windows

1. Install SuperCollider and SC3-plugins.
2. Install an ASIO driver exposing sufficient channels (e.g., VB-Audio Matrix ASIO).

### Linux

1. Install SuperCollider and SC3-plugins from your distribution or source.
2. Use JACK with an interface/session configured for the desired I/O channel count.

## Usage

### With aKMControl (recommended)

The intended workflow is to control aKMServer from [aKMControl](https://github.com/contactlaplanque/akm-control), which handles launching and stopping the server and provides the real‑time UI.

By default, aKMServer listens on `127.0.0.1:23446` and sends ACK/heartbeat to `127.0.0.1:23444`. Adjust `~oscReceivePort` and `~oscSendNetAddr` in the script if needed.

### SuperCollider IDE

1. Open `akM_spatServer.scd` in the SC IDE.
2. Evaluate the entire file. When you see "AKM SPAT SERVER READY" in the post window, the server is running and listening for OSC.

Audio device configuration (optional, edit near the top of the script):

```supercollider
// Examples; pick one model depending on your OS/setup
// s.options.inDevice = "VB-Matrix VASIO-64A"; // Windows example with VB Audio Matrix
// s.options.outDevice = "VB-Matrix VASIO-64A";
s.options.device = "JackRouter";
s.options.sampleRate = 48000;
// Channel counts (match your hardware/session):
// Inputs: number of sources; Outputs: satellites + subs
s.options.numInputBusChannels = 32; // default in script
s.options.numOutputBusChannels = 14; // 12 sats + 2 subs
```

### Command line (sclang)

You can run the server headless from a terminal.

- macOS:

```bash
/Applications/SuperCollider.app/Contents/MacOS/sclang /absolute/path/to/akM_spatServer.scd
```

- Linux:

```bash
sclang /absolute/path/to/akM_spatServer.scd
```

- Windows (PowerShell/CMD):

```bat
sclang.exe C:\absolute\path\to\akM_spatServer.scd
```

## How it Works

High‑level flow:

- For each source (up to 32), a control‑rate panner synth computes per‑speaker gains and time‑of‑flight delays from source position, radius, and exponent.
- An audio‑rate synth reads the hardware input for that source, applies the computed gains/delays, and splits dry vs. reverb‑send.
- A multichannel reverb processes the satellites’ pre‑FX bus.
- A filter stage applies high‑pass on satellites and low‑pass on subs, plus system and per‑speaker gains.
- Per‑speaker parametric EQs run on each satellite and sub.

Key components:

- Speakers layout: 12 satellites + 2 subs with example 3D positions defined in the script.
- Per‑source parameters (7): posX, posY, posZ, radius, exponent `a`, delayLevel, reverbMix.
- Per‑speaker gains: individual dB controls for each satellite and sub.
- System gain: dB value applied post‑FX.
- Filters: satellites (RHPF), subs (RLPF), each with `freq` and `rq`.
- EQ: per speaker, 5 bands (low shelf, 3 peaks, high shelf), 21 parameters.
- Heartbeat: 1 Hz OSC status ping when running.

<a id="panning-algorithm"></a>

## Panning Algorithm: Radius‑limited inverse‑distance panning (kNN‑style)

Let the source be at position $\mathbf{x} \in \mathbb{R}^3$ and the speakers be indexed by $i = 1,\dots,N$ with fixed positions $\mathbf{s}_i \in \mathbb{R}^3$. Define the Euclidean distance

```math
d_i \;=\; \lVert \mathbf{x} - \mathbf{s}_i \rVert \;>\; 0
```

(in practice, a very small $\varepsilon$ is added to avoid division by zero when $\mathbf{x}$ is nearly on top of a speaker).

User‑controlled per‑source parameters:

- $R > 0$: radius of influence (meters). Only speakers strictly inside this radius are considered.
- $a > 0$: distance exponent; larger $a$ concentrates energy on nearer speakers, amking the source feel more _"localized"_
- $L \ge 0$: delay level (unitless scale applied to time‑of‑flight).

Speaker array constants (layout‑dependent):

- $c \approx 344\;\text{m/s}$: speed of sound in air.
- $\boldsymbol{\mu}$: speakers centroid; $R_{\max} > 0$: a characteristic array radius.

1. Select the active neighborhood: the subset of speakers in side the source radius

```math
S \;=\; \{\, i \;\mid\; d_i < R \,\}
```

> [!NOTE]
> Only indices in $S$ can receive nonzero gain (a radius‑limited, kNN‑style selection where $k$ adapts to geometry).

2. Compute unnormalized inverse‑distance weights

```math
w_i \;=\; \frac{\mathbb{1}_{\{i \in S\}}}{d_i^{\,a}} \;=\; \begin{cases}
\dfrac{1}{d_i^{\,a}} & i \in S \\
0 & i \notin S
\end{cases}
```

3. L2 normalization (energy normalization)

```math
K \;=\; \sqrt{\sum_{j\in S} w_j^{\,2}}\,,\qquad
g_i \;=\; \begin{cases}
\dfrac{w_i}{K} & i \in S \\
0 & i \notin S
\end{cases}
```

> [!NOTE]
> If $S = \varnothing$ (no speakers within $R$) or $K = 0$, set all $g_i = 0$. With this normalization, $\sum_i g_i^{\,2} = 1$ whenever $S \ne \varnothing$.

Interpretation: $g_i$ are nonnegative gains that share energy among nearby speakers. Increasing $a$ sharpens localization (more weight to closer speakers). Increasing $R$ includes more speakers in the neighborhood.

4. Time‑of‑flight delays

```math
t_i \;=\; \left(\dfrac{d_i}{c}\right)\,L
```

This is the physical propagation time scaled by $L$. In the implementation, the delay unit squares this time (i.e., uses $t_i^{\,2}$) as a practical shaping—keep $L$ small to remain in a perceptually reasonable range.

5. Distance‑to‑array level attenuation

Let $d_{\mathrm{centroid}} = \lVert \mathbf{x} - \boldsymbol{\mu} \rVert$. Define

```math
p \;=\; 1 + \left(\dfrac{d_{\mathrm{centroid}}}{R_{\max}}\right)^{\!q},\qquad
f\big(d_{\mathrm{centroid}}\big) \;=\; \dfrac{1}{1 + \alpha\,\left(\dfrac{d_{\mathrm{centroid}}}{R_{\max}}\right)^{\!p}}\,,\quad \alpha = 0.04,\; q = 0.2
```

This monotonically decreasing curve gently reduces the source input level as it moves away from the speaker array centroid. The factor $f$ multiplies the source’s audio before panning.

6. Putting it together (per speaker channel $i$)

Let $x_a(t)$ be the source’s input audio signal and $\operatorname{Delay}_{t}(\cdot)$ a delay by $t$ seconds. The dry per‑speaker signal is

```math
y_i(t) \;=\; g_i\;\operatorname{Delay}_{\,t_i}\!\big(\,x_a(t)\,f(d_{\mathrm{centroid}})\big)
```

The script also creates a parallel reverb send (scaled by a per‑source reverb mix) and then applies system/speaker gains, crossover‑style filters (RHPF for satellites, RLPF for subs), and per‑speaker parametric EQ.

## OSC API

All endpoints are on `127.0.0.1` by default. The server listens on `:23446` and sends ACKs to `:23444`.

| Category          | Direction | Address                       | Payload                                                                                                                                                                                               | ACK                                                 |
| ----------------- | --------- | ----------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------- |
| Per‑source params | Send      | `/source{i}/params`           | `posX posY posZ radius exponentA delayLevel reverbMix`                                                                                                                                                | `/akMserver/ack/source{i}/params` (echoes 7 values) |
| System reverb     | Send      | `/system/reverb`              | `decay feedback`                                                                                                                                                                                      | `/akMserver/ack/system/reverb`                      |
| System gain       | Send      | `/system/gain`                | `dB`                                                                                                                                                                                                  | `/akMserver/ack/system/gain`                        |
| Filters (sats)    | Send      | `/system/filter/sats`         | `freq rq`                                                                                                                                                                                             | `/akMserver/ack/system/filter/sats`                 |
| Filters (subs)    | Send      | `/system/filter/subs`         | `freq rq`                                                                                                                                                                                             | `/akMserver/ack/system/filter/subs`                 |
| Satellite gain    | Send      | `/sat{i}/gain`                | `dB`                                                                                                                                                                                                  | `/akMserver/ack/sat{i}/gain`                        |
| Sub gain          | Send      | `/sub{i}/gain`                | `dB`                                                                                                                                                                                                  | `/akMserver/ack/sub{i}/gain`                        |
| Satellite EQ      | Send      | `/sat{i}/eq`                  | 21 params: `EQon, LSh_on, LSh_freq, LSh_gain, LSh_rs, PK1_on, PK1_freq, PK1_gain, PK1_rq, PK2_on, PK2_freq, PK2_gain, PK2_rq, PK3_on, PK3_freq, PK3_gain, PK3_rq, HSh_on, HSh_freq, HSh_gain, HSh_rs` | `/akMserver/ack/sat{i}/eq`                          |
| Sub EQ            | Send      | `/sub{i}/eq`                  | same 21‑param layout as satellites                                                                                                                                                                    | `/akMserver/ack/sub{i}/eq`                          |
| Quit              | Send      | `/quit`                       | none                                                                                                                                                                                                  | `/akMserver/ack/quit` (server stops)                |
| Heartbeat         | Receive   | `/akMserver/status/heartbeat` | `1` every second when running                                                                                                                                                                         | —                                                   |

## Credits and Support

aKM is a project developped within _laplanque_, a non-profit for artistic
creation and the sharing of expertise, bringing together multifaceted artists working in both analog and digital media.

More details: [WEBSITE](https://laplanque.eu/) / [DISCORD](https://discord.gg/c7PK5h3PKE) / [INSTAGRAM](https://www.instagram.com/contact.laplanque/)

- The aKM Project is developped by: Vincent Bergeron, Samy Bérard, Nicolas Désilles
- Software design and development: [Nicolas Désilles](https://github.com/nicolasdesilles). The initial development of the first protoype was conducted with the help from [Rémi Georges](https://remigeorges.fr/), during a technical residency at [GRAME CNCM](https://www.grame.fr/), Lyon, FR.

- kNN-like Audio Panning Algorithm inspired from Stewart Blackwood's Master Thesis at the University of California San Diego: [Blackwood, S. (2022). A Methodology for Creating Theatrical Spatial Sound Experiences](https://escholarship.org/content/qt474028vj/qt474028vj_noSplash_c2153d43228befb994c79d245235e76b.pdf)

- Multichannel reverb adapted from Yota Morimoto’s n‑channel reverb example ([github](https://github.com/yotamorimoto/sclab/blob/main/nchannel_verb.scd))

- Supporters: La Région AURA, GRAME CNCM, la Métropole de Lyon, Hangar Computer Club, and private contributors

![logos-partenaires](https://laplanque.eu/wp-content/uploads/2025/07/LOGO-partenaire-siteweb.png)

## License

GNU GPL‑3.0. See `LICENSE`.

## Notes

- This is a pre‑release prototype and defaults (I/O counts, device names, speaker layout, centroid/radius constants) may change. The centroid, speaker configurations, and `R_max` are currently hard‑coded placeholders in the script pending a configuration‑driven layout.
- Proper documentation for users and developpers will follow soon

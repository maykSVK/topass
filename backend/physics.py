import cv2
import numpy as np
import random
import math
from typing import List, Dict, Any, Optional

# ─── Musical Harmony ─────────────────────────────────────────────────────────
# Hans Zimmer style: modal harmonies, pedal tones, ambiguous chords.
# Progressions inspired by: Inception, Interstellar, Gladiator.

def build_chord(root, offsets, octaves=3):
    """Builds a chord spanning multiple octaves."""
    chord = []
    for oct in range(octaves):
        for offset in offsets:
            note = root + offset + (oct * 12)
            if 40 <= note <= 88:  # Keep within reasonable MIDI range
                chord.append(note)
    return sorted(list(set(chord)))

# Define root notes (C3 = 48)
C = 48; Db = 49; D = 50; Eb = 51; E = 52; F = 53; Gb = 54; G = 55; Ab = 56; A = 57; Bb = 58; B = 59

# Define chord qualities (intervals from root)
MAJ     = [0, 4, 7, 11]   # Maj7
MIN     = [0, 3, 7, 10]   # Min7
SUS2    = [0, 2, 7]       # Sus2 (open, ambiguous – HZ signature)
SUS4    = [0, 5, 7]       # Sus4
ADD9    = [0, 4, 7, 14]   # Add9 (bright, cinematic)
MINMAJ7 = [0, 3, 7, 11]   # Min/Maj7 (tense, mysterious)
POWER   = [0, 7]          # Power chord (raw, epic)

# ─── Hans Zimmer Chord Progressions ──────────────────────────────────────────

# "INCEPTION" style – Dorian, pedal bass on A, hypnotic ostinato
# Am7 → G/A → Fmaj7 → Em7  (all over A pedal)
INCEPTION_PROG = [
    build_chord(A,  MIN),       # Am7
    build_chord(G,  SUS2),      # G sus2 (over A pedal in bass)
    build_chord(F,  ADD9),      # Fmaj9
    build_chord(E,  MIN),       # Em7
]

# "INTERSTELLAR" style – Aeolian, slow epic swells, open 5ths
# Cm → Gm → Ab → Bb → Cm
INTERSTELLAR_PROG = [
    build_chord(C,  SUS2),      # C open/sus2 (no 3rd – ambiguous)
    build_chord(G,  POWER),     # G5 power chord
    build_chord(Ab, MAJ),       # Abmaj (bVI – HZ favourite lift)
    build_chord(Bb, SUS4),      # Bb sus4 (building tension)
]

# "GLADIATOR" style – Phrygian Dominant / Andalusian cadence
# Dm → C → Bb → A  (descending bass line)
GLADIATOR_PROG = [
    build_chord(D,  MIN),       # Dm
    build_chord(C,  MAJ),       # C major
    build_chord(Bb, ADD9),      # Bb add9
    build_chord(A,  MAJ),       # A major (Phrygian dominant resolution)
]

CHORD_PROGS = {
    "inception":     INCEPTION_PROG,
    "interstellar":  INTERSTELLAR_PROG,
    "gladiator":     GLADIATOR_PROG,
}

# Pedal tones for each progression (bass stays on this note longer)
PEDAL_TONES = {
    "inception":    A - 12,   # A2 – deep pedal under entire progression
    "interstellar": C - 12,   # C2 – low C pedal
    "gladiator":    D - 12,   # D2 – Dm root pedal
}

# ─── Rhythm ──────────────────────────────────────────────────────────────────
BEAT       = 40   # frames per quarter note @ ~58 BPM (slower = more cinematic)
HALF_BEAT  = 20
CHORD_DUR  = BEAT * 16  # Chord changes every 4 bars (16 beats)

# ─── Voice configuration ─────────────────────────────────────────────────────
# (period_frames, offset_frames, register_bias, rest_prob)
# Voices are: bass, pad, cello, violin, piano/melody, tick-percussion
VOICE_CONFIG = [
    (BEAT * 8,  0,          0.1,  0.0),    # 0  bass (every 2 bars, never rests)
    (BEAT * 8,  0,          0.3,  0.05),   # 1  pad (very long, slow swells)
    (BEAT * 2,  0,          0.45, 0.25),   # 2  cello ostinato (every 2 beats)
    (BEAT * 2,  BEAT,       0.55, 0.30),   # 3  violin ostinato (offset by 1 beat)
    (BEAT,      0,          0.78, 0.50),   # 4  piano melody (sparse, melodic)
    (HALF_BEAT, HALF_BEAT,  0.5,  0.60),   # 5  tick percussion (Inception clock)
]

LOCO_MODES = ["downhill", "uphill", "contour", "explorer"]
JITTER     = 2    # reduced from 3 for tighter timing
NUM_AGENTS = 12

# ─── Melodic Phrase Builder ───────────────────────────────────────────────────
# Each melody agent maintains a phrase: a sequence of directed scale steps.
# When the phrase is exhausted, a new one is generated (arch shape: up then down).
PHRASE_LEN_RANGE = (4, 8)   # notes per phrase

class MelodyPhrase:
    """Generates Hans Zimmer style melodic phrases: arch-shaped, step-wise motion."""
    def __init__(self):
        self.steps: List[int] = []   # signed semitone steps
        self.pos: int = 0
        self._new_phrase()

    def _new_phrase(self):
        """Create a new arch-shaped phrase (ascent → peak → descent)."""
        length = random.randint(*PHRASE_LEN_RANGE)
        # Small stepwise intervals: mostly 1–3 semitones, occasionally a 4th (5 st)
        step_choices = [-5, -4, -3, -2, -1, 1, 2, 3, 4, 5]
        # Arch: first half goes up, second half comes down
        half = length // 2
        up_steps   = [random.choice([1, 2, 2, 3, 4]) for _ in range(half)]
        down_steps = [-s for s in reversed(up_steps)]
        # Add a small tail variation
        tail = [random.choice(step_choices) for _ in range(length - 2 * half)]
        self.steps = up_steps + down_steps + tail
        self.pos = 0

    def next_step(self) -> int:
        """Return the next step in semitones and advance position."""
        if self.pos >= len(self.steps):
            self._new_phrase()
        step = self.steps[self.pos]
        self.pos += 1
        return step


class Agent:
    def __init__(self, id: int, x: float, y: float, mass: float = 1.0, loco_mode: str = "downhill"):
        self.id = id
        self.x = x
        self.y = y
        self.vx = 0.0
        self.vy = 0.0
        # EMA smoothed velocities for graceful movement
        self.smooth_vx = 0.0
        self.smooth_vy = 0.0
        self.mass = mass
        self.loco_mode = loco_mode
        self.path: List[Dict] = []
        self.events: List[Dict] = []
        self.prev_z: int = -1
        self.last_pitch: Optional[int] = None
        # Melodic phrase for voice 4 agents
        self.phrase = MelodyPhrase() if (id % len(VOICE_CONFIG) == 4) else None
        # Ostinato step counter for voices 2 & 3
        self.ostinato_step: int = 0

    def get_speed(self) -> float:
        return math.sqrt(self.vx ** 2 + self.vy ** 2)


class Simulation:
    def __init__(self, image_bytes: bytes, num_agents: int = NUM_AGENTS, frames: int = 400, contour_interval: int = 10):
        np_arr = np.frombuffer(image_bytes, np.uint8)
        self.img_gray = cv2.imdecode(np_arr, cv2.IMREAD_GRAYSCALE)
        if self.img_gray is None:
            raise ValueError("Failed to decode image")

        self.height, self.width = self.img_gray.shape
        self.num_agents = num_agents
        self.frames = frames
        self.contour_interval = contour_interval

        self.image_stats = self._compute_image_stats()
        self.prog_name = self.image_stats["scale"]
        self.progression = CHORD_PROGS[self.prog_name]
        self.pedal_tone = PEDAL_TONES[self.prog_name]

        self.grad_x = cv2.Sobel(self.img_gray, cv2.CV_64F, 1, 0, ksize=5)
        self.grad_y = cv2.Sobel(self.img_gray, cv2.CV_64F, 0, 1, ksize=5)
        mx = np.max(np.abs(self.grad_x))
        my = np.max(np.abs(self.grad_y))
        if mx > 0: self.grad_x /= mx
        if my > 0: self.grad_y /= my

        # Gaussian blur on gradient for smoother force field
        self.grad_x = cv2.GaussianBlur(self.grad_x, (11, 11), 0)
        self.grad_y = cv2.GaussianBlur(self.grad_y, (11, 11), 0)

        self.agents = self._init_agents()

    def _init_agents(self) -> List[Agent]:
        n = self.num_agents
        cols = 4
        rows = math.ceil(n / cols)
        agents = []
        margin = 20

        for i in range(n):
            col = i % cols
            row = i // cols
            cell_w = (self.width  - 2 * margin) / cols
            cell_h = (self.height - 2 * margin) / rows
            x = margin + col * cell_w + random.uniform(0, cell_w)
            y = margin + row * cell_h + random.uniform(0, cell_h)
            x = max(margin, min(self.width  - margin, x))
            y = max(margin, min(self.height - margin, y))
            mass = random.uniform(0.8, 1.5)
            loco = LOCO_MODES[i % len(LOCO_MODES)]
            agents.append(Agent(i, x, y, mass, loco))
        return agents

    def _compute_image_stats(self) -> Dict[str, Any]:
        mean_b = float(np.mean(self.img_gray))
        std_b  = float(np.std(self.img_gray))
        edges  = cv2.Canny(self.img_gray, 50, 150)
        edge_density = float(np.count_nonzero(edges)) / (self.width * self.height)

        # Map brightness to HZ progression style
        # Bright  → Inception (dreamy, hypnotic Dorian)
        # Medium  → Interstellar (epic, open Aeolian)
        # Dark    → Gladiator (dark, Phrygian dominant)
        scale = "inception" if mean_b > 160 else ("gladiator" if mean_b < 90 else "interstellar")

        tempo_mult  = round(max(0.5, min(2.0, 0.5 + std_b / 128.0)), 2)
        timbre_hint = round(min(edge_density * 10, 1.0), 2)

        return {
            "scale":            scale,
            "mean_brightness":  round(mean_b, 1),
            "std_brightness":   round(std_b, 1),
            "edge_density":     round(edge_density, 4),
            "tempo_multiplier": tempo_mult,
            "timbre_hint":      timbre_hint,
        }

    def _get_pitch_for_voice(self, current_chord: List[int], agent: Agent,
                              register_bias: float, current_z: int, voice_id: int) -> int:
        """Selects a musical note using HZ-style voice leading."""
        if not current_chord:
            return 60

        # ── Voice 4: Piano melody – arch phrase builder ──────────────────────
        if voice_id == 4 and agent.phrase is not None:
            if agent.last_pitch is None:
                # Start from a chord tone near the melody register
                target_idx = int(register_bias * (len(current_chord) - 1))
                pitch = current_chord[target_idx]
            else:
                step = agent.phrase.next_step()
                candidate = agent.last_pitch + step
                # Snap to nearest chord tone (keeps pitch harmonic)
                pitch = min(current_chord, key=lambda p: abs(p - candidate))
            return pitch

        # ── Voices 2 & 3: Cello/Violin ostinato – step through chord tones ──
        if voice_id in (2, 3):
            # Cycle through the chord tones in order → creates arpeggiated ostinato
            chord_len = len(current_chord)
            # Each agent has its own ostinato phase offset
            phase_offset = agent.id * 2
            idx = (agent.ostinato_step + phase_offset) % chord_len
            pitch = current_chord[idx]
            # Constrain to voice register
            low  = int(register_bias * 0.7 * (len(current_chord) - 1))
            high = min(int(register_bias * 1.3 * (len(current_chord) - 1)), chord_len - 1)
            idx_clamped = max(low, min(high, idx))
            pitch = current_chord[idx_clamped]
            agent.ostinato_step += 1
            return pitch

        # ── Default: Z-weighted register selection with step-wise leading ────
        z_mod = (current_z / 255.0 - 0.5) * 0.3
        target_percentile = max(0.0, min(1.0, register_bias + z_mod))
        target_idx = int(target_percentile * (len(current_chord) - 1))
        pitch = current_chord[target_idx]

        if agent.last_pitch is not None:
            step_direction = 1 if current_z > agent.prev_z else -1
            # HZ style: prefer small steps (1–3 semitones)
            ideal_pitch = agent.last_pitch + (step_direction * random.choice([1, 2, 2, 3]))
            # Snap to nearest chord tone, weighted toward register target
            pitch = min(current_chord, key=lambda p: abs(p - ideal_pitch) * 0.6 + abs(p - current_chord[target_idx]) * 0.4)

        return pitch

    def _velocity_for(self, agent: Agent, ix: int, iy: int, base: int = 70) -> int:
        """Compute MIDI velocity – calmer baseline for HZ style (fewer loud pops)."""
        x0, x1 = max(0, ix - 7), min(self.width,  ix + 7)
        y0, y1 = max(0, iy - 7), min(self.height, iy + 7)
        patch = self.img_gray[y0:y1, x0:x1]
        local_contrast = float(np.std(patch)) if patch.size > 0 else 0.0
        contrast_v = int((local_contrast / 128.0) * 20)
        speed_v    = int(min((agent.get_speed() / 4.0) * 15, 15))
        return max(40, min(100, base + contrast_v + speed_v + random.randint(-3, 3)))

    def _physics_force(self, agent: Agent, ix: int, iy: int):
        gx = self.grad_x[iy, ix]
        gy = self.grad_y[iy, ix]

        if agent.loco_mode == "downhill":
            return -gx * 1.2, -gy * 1.2
        elif agent.loco_mode == "uphill":
            return gx * 1.0, gy * 1.0
        elif agent.loco_mode == "contour":
            sign = 1 if agent.id % 2 == 0 else -1
            mag = math.sqrt(gx**2 + gy**2) + 1e-9
            return sign * (-gy / mag) * 1.1, sign * (gx / mag) * 1.1
        else:
            # Explorer: weak gradient pull (not pure random anymore)
            return -gx * 0.4, -gy * 0.4

    def _apply_repulsion(self, agents: List[Agent]) -> List[tuple]:
        forces = [(0.0, 0.0)] * len(agents)
        repulsion_radius = min(self.width, self.height) * 0.10
        repulsion_strength = 0.5  # reduced for less jittery behaviour

        for i in range(len(agents)):
            fx, fy = 0.0, 0.0
            for j in range(len(agents)):
                if i == j: continue
                dx = agents[i].x - agents[j].x
                dy = agents[i].y - agents[j].y
                dist = math.sqrt(dx**2 + dy**2) + 1e-9
                if dist < repulsion_radius:
                    strength = repulsion_strength * (1.0 - dist / repulsion_radius)
                    fx += (dx / dist) * strength
                    fy += (dy / dist) * strength
            forces[i] = (fx, fy)
        return forces

    def run(self) -> Dict[str, Any]:
        # ── Physics constants ────────────────────────────────────────────────
        friction     = 0.96   # was 0.92 – smoother, longer glide
        ema_alpha    = 0.18   # EMA smoothing for velocity (lower = more smoothing)
        max_speed    = 3.0    # hard cap to prevent sudden dashes

        # Much lower noise per mode – agents follow the landscape melodically
        noise_by_mode = {
            "downhill": 0.04,
            "uphill":   0.04,
            "contour":  0.03,
            "explorer": 0.25,  # was 1.20 – still the most random but controlled
        }

        # ── Pedal tone scheduling ────────────────────────────────────────────
        # Bass voice plays the pedal tone for the first 3 chords, then root
        PEDAL_HOLD_CHORDS = 3   # hold pedal for this many chord changes

        for frame in range(self.frames):
            chord_idx  = (frame // CHORD_DUR) % len(self.progression)
            chord_num  = frame // CHORD_DUR   # absolute chord count
            current_chord = self.progression[chord_idx]

            repulsion_forces = self._apply_repulsion(self.agents)

            for agent in self.agents:
                agent.path.append({"x": round(agent.x, 2), "y": round(agent.y, 2)})

                ix = max(0, min(self.width  - 1, int(agent.x)))
                iy = max(0, min(self.height - 1, int(agent.y)))
                current_z = int(self.img_gray[iy, ix])

                # ── Musical scheduling ───────────────────────────────────────
                voice_id = agent.id % len(VOICE_CONFIG)
                period, offset, register_bias, rest_prob = VOICE_CONFIG[voice_id]

                if period > 0 and (frame - offset) % period == 0 and frame >= offset:
                    if random.random() > rest_prob:

                        # ── Voice 0: Bass – pedal tone logic ────────────────
                        if voice_id == 0:
                            if chord_num < PEDAL_HOLD_CHORDS:
                                pitch = self.pedal_tone   # hold deep pedal
                            else:
                                # Slowly walk the bass: alternate root and fifth
                                root = current_chord[0]
                                fifth = root + 7 if (root + 7) <= 88 else root
                                pitch = root if (chord_num % 2 == 0) else fifth
                        else:
                            pitch = self._get_pitch_for_voice(
                                current_chord, agent, register_bias, current_z, voice_id
                            )

                        agent.last_pitch = pitch
                        velocity = self._velocity_for(agent, ix, iy)
                        jitter = random.randint(-JITTER, JITTER)

                        agent.events.append({
                            "frame":    max(0, frame + jitter),
                            "pitch":    pitch,
                            "velocity": velocity,
                            "z":        current_z,
                            "voice":    voice_id,
                        })

                agent.prev_z = current_z

                # ── Physics with EMA smoothing ───────────────────────────────
                fx, fy   = self._physics_force(agent, ix, iy)
                rfx, rfy = repulsion_forces[agent.id]

                # Raw velocity update
                raw_vx = agent.vx + (fx + rfx) / agent.mass
                raw_vy = agent.vy + (fy + rfy) / agent.mass

                # Low-pass / EMA smoothing: blends toward new velocity gradually
                agent.smooth_vx = ema_alpha * raw_vx + (1 - ema_alpha) * agent.smooth_vx
                agent.smooth_vy = ema_alpha * raw_vy + (1 - ema_alpha) * agent.smooth_vy

                # Minimal noise (much less chaotic than before)
                noise = noise_by_mode[agent.loco_mode]
                agent.smooth_vx += random.uniform(-noise, noise)
                agent.smooth_vy += random.uniform(-noise, noise)

                # Friction on smoothed velocity
                agent.smooth_vx *= friction
                agent.smooth_vy *= friction

                # Hard speed cap
                speed = math.sqrt(agent.smooth_vx**2 + agent.smooth_vy**2)
                if speed > max_speed:
                    scale = max_speed / speed
                    agent.smooth_vx *= scale
                    agent.smooth_vy *= scale

                agent.vx = agent.smooth_vx
                agent.vy = agent.smooth_vy

                agent.x += agent.vx
                agent.y += agent.vy

                if agent.x < 0:
                    agent.x = 0; agent.vx *= -0.5; agent.smooth_vx *= -0.5
                elif agent.x >= self.width:
                    agent.x = self.width - 1; agent.vx *= -0.5; agent.smooth_vx *= -0.5
                if agent.y < 0:
                    agent.y = 0; agent.vy *= -0.5; agent.smooth_vy *= -0.5
                elif agent.y >= self.height:
                    agent.y = self.height - 1; agent.vy *= -0.5; agent.smooth_vy *= -0.5

        for agent in self.agents:
            agent.events.sort(key=lambda e: e["frame"])

        return {
            "width":       self.width,
            "height":      self.height,
            "image_stats": self.image_stats,
            "agents": [{
                "id":     a.id,
                "path":   a.path,
                "events": a.events,
                "mass":   a.mass,
            } for a in self.agents],
        }

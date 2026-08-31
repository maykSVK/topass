import cv2
import numpy as np
import random
import math
from typing import List, Dict, Any, Optional

# ─── Musical Harmony ────────────────────────────────────────────────────────
# Instead of random scale steps, we use Functional Harmony (Chords).
# Each scale is defined by a set of chords (I, ii, iii, IV, V, vi, vii°, etc.)
# A chord is a list of pitches [Root, 3rd, 5th, 7th].

def build_chord(root, offsets, octaves=3):
    """Builds a chord spanning multiple octaves."""
    chord = []
    for oct in range(octaves):
        for offset in offsets:
            note = root + offset + (oct * 12)
            if 40 <= note <= 88: # Keep within reasonable MIDI range
                chord.append(note)
    return sorted(list(set(chord)))

# Define root notes (C3 = 48)
C = 48; Db = 49; D = 50; Eb = 51; E = 52; F = 53; Gb = 54; G = 55; Ab = 56; A = 57; Bb = 58; B = 59

# Define chord qualities (intervals from root)
MAJ = [0, 4, 7, 11]  # Maj7
MIN = [0, 3, 7, 10]  # Min7
DIM = [0, 3, 6, 10]  # Half-dim7

# Define Progressions based on image mood
# Lydian (Bright): Imaj7 -> IImaj7 -> vim7 -> Vmaj7
LYDIAN_PROG = [
    build_chord(C, MAJ),
    build_chord(D, MAJ),
    build_chord(A, MIN),
    build_chord(G, MAJ),
]

# Minor (Mid): im7 -> VImaj7 -> IIImaj7 -> Vm7
MINOR_PROG = [
    build_chord(A, MIN),
    build_chord(F, MAJ),
    build_chord(C, MAJ),
    build_chord(E, MIN),
]

# Phrygian (Dark): im7 -> bIImaj7 -> ivm7 -> Vm7 (Phrygian dominant feel)
PHRYGIAN_PROG = [
    build_chord(C, MIN),
    build_chord(Db, MAJ),
    build_chord(F, MIN),
    build_chord(G, MIN),
]

CHORD_PROGS = {
    "lydian": LYDIAN_PROG,
    "minor": MINOR_PROG,
    "phrygian": PHRYGIAN_PROG,
}

# ─── Rhythm ──────────────────────────────────────────────────────────────────
BEAT      = 33   # frames per quarter note @ 72 BPM
HALF_BEAT = 17
CHORD_DUR = BEAT * 16 # Chord changes every 4 bars (16 beats)

# ─── Voice configuration ─────────────────────────────────────────────────────
# (period_frames, offset_frames, register_bias, rest_prob)
VOICE_CONFIG = [
    (BEAT * 4,  0,          0.1,  0.0),    # 0  bass (plays exactly on downbeats, never rests)
    (BEAT * 8,  0,          0.3,  0.1),    # 1  pad (long slow chords)
    (BEAT * 2,  0,          0.5,  0.35),   # 2  inner_low (mid)
    (BEAT,      BEAT,       0.6,  0.45),   # 3  inner_high (mid-high)
    (BEAT,      0,          0.8,  0.55),   # 4  melody (high, sparse, melodic phrases)
    (HALF_BEAT, HALF_BEAT,  0.9,  0.75),   # 5  ornament (highest, rare fast sprinkles)
]

LOCO_MODES = ["downhill", "uphill", "contour", "explorer"]
JITTER = 3
NUM_AGENTS = 12

class Agent:
    def __init__(self, id: int, x: float, y: float, mass: float = 1.0, loco_mode: str = "downhill"):
        self.id = id
        self.x = x
        self.y = y
        self.vx = 0.0
        self.vy = 0.0
        self.mass = mass
        self.loco_mode = loco_mode
        self.path: List[Dict] = []
        self.events: List[Dict] = []
        self.prev_z: int = -1
        self.last_pitch: Optional[int] = None

    def get_speed(self) -> float:
        return math.sqrt(self.vx ** 2 + self.vy ** 2)

class Simulation:
    def __init__(self, image_bytes: bytes, num_agents: int = NUM_AGENTS, frames: int = 400, contour_interval: int = 10):
        np_arr = np.frombuffer(image_bytes, np.uint8)
        self.img_gray = cv2.imdecode(np_arr, cv2.IMREAD_GRAYSCALE)
        if self.img_gray is None: raise ValueError("Failed to decode image")

        self.height, self.width = self.img_gray.shape
        self.num_agents = num_agents
        self.frames = frames
        self.contour_interval = contour_interval

        self.image_stats = self._compute_image_stats()
        self.progression = CHORD_PROGS[self.image_stats["scale"]]

        self.grad_x = cv2.Sobel(self.img_gray, cv2.CV_64F, 1, 0, ksize=5)
        self.grad_y = cv2.Sobel(self.img_gray, cv2.CV_64F, 0, 1, ksize=5)
        mx = np.max(np.abs(self.grad_x))
        my = np.max(np.abs(self.grad_y))
        if mx > 0: self.grad_x /= mx
        if my > 0: self.grad_y /= my

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

        scale = "lydian" if mean_b > 160 else ("phrygian" if mean_b < 90 else "minor")
        tempo_mult  = round(max(0.5, min(2.0, 0.5 + std_b / 128.0)), 2)
        timbre_hint = round(min(edge_density * 10, 1.0), 2)

        return {
            "scale": scale,
            "mean_brightness":  round(mean_b, 1),
            "std_brightness":   round(std_b, 1),
            "edge_density":     round(edge_density, 4),
            "tempo_multiplier": tempo_mult,
            "timbre_hint":      timbre_hint,
        }

    def _get_pitch_for_voice(self, current_chord: List[int], agent: Agent, register_bias: float, current_z: int) -> int:
        """Selects a musical note from the current chord based on voice register and topography."""
        if not current_chord: return 60
        
        # Target index in the chord based on the voice's register bias + local topography (Z)
        # Z-height slightly shifts the note up or down within its register
        z_mod = (current_z / 255.0 - 0.5) * 0.4 # +/- 20% shift
        target_percentile = max(0.0, min(1.0, register_bias + z_mod))
        
        target_idx = int(target_percentile * (len(current_chord) - 1))
        
        # Introduce step-wise voice leading: don't jump too far from last pitch
        pitch = current_chord[target_idx]
        if agent.last_pitch is not None:
            # Find closest chord tone to (last_pitch + small step)
            step_direction = 1 if current_z > agent.prev_z else -1
            ideal_pitch = agent.last_pitch + (step_direction * random.choice([0, 2, 3, 4]))
            
            # Snap ideal_pitch to the nearest note in current_chord within a reasonable range of target
            closest_pitch = min(current_chord, key=lambda p: abs(p - ideal_pitch) + abs(p - pitch)*0.5)
            pitch = closest_pitch
            
        return pitch

    def _velocity_for(self, agent: Agent, ix: int, iy: int, base: int = 75) -> int:
        x0, x1 = max(0, ix - 7), min(self.width,  ix + 7)
        y0, y1 = max(0, iy - 7), min(self.height, iy + 7)
        patch = self.img_gray[y0:y1, x0:x1]
        local_contrast = float(np.std(patch)) if patch.size > 0 else 0.0
        contrast_v = int((local_contrast / 128.0) * 30)
        speed_v    = int(min((agent.get_speed() / 4.0) * 20, 20))
        return max(40, min(110, base + contrast_v + speed_v + random.randint(-5, 5)))

    def _physics_force(self, agent: Agent, ix: int, iy: int):
        gx = self.grad_x[iy, ix]
        gy = self.grad_y[iy, ix]

        if agent.loco_mode == "downhill": return -gx * 1.5, -gy * 1.5
        elif agent.loco_mode == "uphill": return gx * 1.2, gy * 1.2
        elif agent.loco_mode == "contour":
            sign = 1 if agent.id % 2 == 0 else -1
            mag = math.sqrt(gx**2 + gy**2) + 1e-9
            return sign * (-gy / mag) * 1.3, sign * (gx / mag) * 1.3
        else:
            return -gx * 0.3, -gy * 0.3

    def _apply_repulsion(self, agents: List[Agent]) -> List[tuple]:
        forces = [(0.0, 0.0)] * len(agents)
        repulsion_radius = min(self.width, self.height) * 0.12
        repulsion_strength = 0.8

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
        friction = 0.92
        noise_by_mode = {"downhill": 0.25, "uphill": 0.25, "contour": 0.20, "explorer": 1.20}

        for frame in range(self.frames):
            # Determine current chord based on frame number (Harmonic Progression)
            chord_idx = (frame // CHORD_DUR) % len(self.progression)
            current_chord = self.progression[chord_idx]
            
            repulsion_forces = self._apply_repulsion(self.agents)

            for agent in self.agents:
                agent.path.append({"x": round(agent.x, 2), "y": round(agent.y, 2)})

                ix = max(0, min(self.width  - 1, int(agent.x)))
                iy = max(0, min(self.height - 1, int(agent.y)))
                current_z = int(self.img_gray[iy, ix])

                # ── Musical scheduling ──
                voice_id = agent.id % len(VOICE_CONFIG)
                period, offset, register_bias, rest_prob = VOICE_CONFIG[voice_id]

                if period > 0 and (frame - offset) % period == 0 and frame >= offset:
                    if random.random() > rest_prob:
                        pitch = self._get_pitch_for_voice(current_chord, agent, register_bias, current_z)
                        agent.last_pitch = pitch
                        
                        # Bass voice always plays the Root note of the chord in the lowest octave
                        if voice_id == 0:
                            pitch = current_chord[0] 

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

                # ── Physics ──
                fx, fy = self._physics_force(agent, ix, iy)
                rfx, rfy = repulsion_forces[agent.id]
                
                agent.vx += (fx + rfx) / agent.mass
                agent.vy += (fy + rfy) / agent.mass

                noise = noise_by_mode[agent.loco_mode]
                agent.vx += random.uniform(-noise, noise)
                agent.vy += random.uniform(-noise, noise)

                agent.vx *= friction
                agent.vy *= friction

                agent.x += agent.vx
                agent.y += agent.vy

                if agent.x < 0: agent.x = 0; agent.vx *= -0.8
                elif agent.x >= self.width: agent.x = self.width - 1; agent.vx *= -0.8
                if agent.y < 0: agent.y = 0; agent.vy *= -0.8
                elif agent.y >= self.height: agent.y = self.height - 1; agent.vy *= -0.8

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

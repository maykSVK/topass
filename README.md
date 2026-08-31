# TopASS – Topographic Agents Sonification System

TopASS is an ambient music simulation platform that translates topographic images into generative musical compositions using physics-based agents and functional harmony.

## How It Works
1. **Topographic Analysis**: You upload an image (e.g., a topographic map). The system analyzes its brightness, contrast, and edge density.
2. **Harmonic Progression**: Based on the image's overall mood (bright vs dark), the system selects a musical scale (Lydian, Minor, or Phrygian) and generates a structured chord progression.
3. **Physics Agents**: 12 independent agents traverse the image using various locomotion modes (downhill, uphill, contour-following, and exploring).
4. **Sonification**: As the agents traverse varying "altitudes" (brightness levels), they trigger notes locked to the current functional chord. The synthesized instruments—ranging from warm bass guitars to ethereal flutes—are processed through a custom Web Audio API synthesizer.

## Project Structure
* `/backend`: FastAPI Python server that runs the topographic analysis, agent physics simulation, and harmonic scheduling.
* `/tass`: Flutter Web frontend that handles the UI, visualizes the agents' paths in a sleek "radar" mode, and plays the synthesized audio.

## Getting Started

### Prerequisites
* **Python 3.10+**
* **Flutter SDK 3.x**

### 1. Run the Backend
```bash
cd backend
pip install -r requirements.txt
python -m uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

### 2. Run the Frontend
Open a new terminal window:
```bash
cd tass
flutter pub get
flutter run -d chrome --web-port=8080
```

Open `http://localhost:8080` in Chrome to access the TopASS Terminal.

## License
MIT License

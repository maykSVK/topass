import 'dart:js_interop';
import 'dart:math';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

class WebAudioSynth {
  web.AudioContext? _ctx;
  web.GainNode? _masterGain;
  web.ConvolverNode? _reverb;
  web.GainNode? _reverbWet;
  web.GainNode? _reverbDry;
  web.DelayNode? _delay;
  web.GainNode? _delayFeedback;
  web.GainNode? _delayWet;
  web.DynamicsCompressorNode? _comp;
  bool _resumed = false;

  WebAudioSynth() {
    try {
      _ctx = web.AudioContext();
      _buildFx();
    } catch (e) {
      // ignore: avoid_print
      print('Web Audio API not supported: $e');
    }
  }

  // ── FX Chain ──────────────────────────────────────────────────────────────
  // Signal flow: voices → masterGain → [dry path + reverb wet path] → compressor → output
  void _buildFx() {
    if (_ctx == null) return;
    final now = _ctx!.currentTime;

    // Master gain (headroom for compression)
    _masterGain = _ctx!.createGain();
    _masterGain!.gain.value = 0.65;

    // ── Compressor (glues the mix, maintains loudness) ──────────────────────
    _comp = _ctx!.createDynamicsCompressor();
    _comp!.threshold.value = -18.0;
    _comp!.knee.value = 8.0;
    _comp!.ratio.value = 4.0;
    _comp!.attack.value = 0.003;
    _comp!.release.value = 0.25;

    // ── Synthetic Hall Reverb ───────────────────────────────────────────────
    // Generated as exponentially-decaying white noise burst (impulse response)
    _reverb    = _ctx!.createConvolver();
    _reverbWet = _ctx!.createGain();
    _reverbDry = _ctx!.createGain();
    _reverbWet!.gain.value = 0.42;  // 42% wet – epic spacious hall
    _reverbDry!.gain.value = 0.58;
    _reverb!.buffer = _buildImpulseResponse(4.5, 2.8, false);

    // ── Short slap-echo delay ───────────────────────────────────────────────
    _delay = _ctx!.createDelay(1.0);
    _delay!.delayTime.value = 0.11;   // tighter slap echo
    _delayFeedback = _ctx!.createGain();
    _delayFeedback!.gain.value = 0.18; // low feedback – just a single echo
    _delayWet = _ctx!.createGain();
    _delayWet!.gain.value = 0.15;

    // ── Wire up ─────────────────────────────────────────────────────────────
    // master → dry path → compressor → output
    _masterGain!.connect(_reverbDry!);
    _reverbDry!.connect(_comp!);

    // master → reverb → wet gain → compressor → output
    _masterGain!.connect(_reverb!);
    _reverb!.connect(_reverbWet!);
    _reverbWet!.connect(_comp!);

    // master → delay → feedback loop → delay
    _masterGain!.connect(_delay!);
    _delay!.connect(_delayFeedback!);
    _delayFeedback!.connect(_delay!);
    _delay!.connect(_delayWet!);
    _delayWet!.connect(_comp!);

    // compressor → output
    _comp!.connect(_ctx!.destination);
  }

  /// Builds a synthetic exponential reverb impulse response.
  web.AudioBuffer _buildImpulseResponse(double duration, double decay, bool reverse) {
    final ctx = _ctx!;
    final sampleRate  = ctx.sampleRate;
    final length      = (sampleRate * duration).round();
    final buffer      = ctx.createBuffer(2, length, sampleRate);
    final rand        = Random();

    for (int ch = 0; ch < 2; ch++) {
      final data = buffer.getChannelData(ch).toDart;
      for (int i = 0; i < length; i++) {
        final n = reverse ? length - i : i;
        data[i] = (rand.nextDouble() * 2 - 1) * pow(1 - n / length, decay);
      }
    }
    return buffer;
  }

  void ensureResumed() {
    if (_ctx == null) return;
    if (!_resumed || _ctx!.state == 'suspended') {
      _ctx!.resume();
      _resumed = true;
    }
  }

  double _freq(int midi) => 440.0 * pow(2.0, (midi - 69) / 12.0);
  double _gain(int velocity, double cap) => (velocity / 127.0) * cap;

  web.StereoPannerNode _panner(double pan) {
    final p = _ctx!.createStereoPanner();
    p.pan.value = pan;
    return p;
  }

  web.BiquadFilterNode _filter(String type, double freq, {double q = 1.0}) {
    final f = _ctx!.createBiquadFilter();
    f.type = type;
    f.frequency.value = freq;
    f.Q.value = q;
    return f;
  }

  web.GainNode _gainNode(double val) {
    final g = _ctx!.createGain();
    g.gain.value = val;
    return g;
  }

  void _envelope(web.AudioParam param, double gainVal,
      double attack, double decay, double sustain, double release, double now) {
    param.setValueAtTime(0.0001, now);
    param.linearRampToValueAtTime(gainVal, now + attack);
    param.linearRampToValueAtTime(gainVal * sustain, now + attack + decay);
    param.setValueAtTime(gainVal * sustain, now + attack + decay + 0.05);
    param.exponentialRampToValueAtTime(0.0001, now + attack + decay + release);
  }

  // ── Voice 0 · Epic Bass ───────────────────────────────────────────────────
  // Sub-bass sine (-24 st) + fundamental + waveshaper harmonic warmth.
  // Long release, slow attack → HZ deep underpinning.
  void _playBass(int pitch, int velocity) {
    final now = _ctx!.currentTime;
    final g = _gain(velocity, 0.80);

    // Sub-bass (−24 semitones = two octaves down)
    final subOsc  = _ctx!.createOscillator();
    final subGain = _gainNode(0);
    subOsc.type = 'sine';
    subOsc.frequency.value = _freq(pitch - 12);  // one octave below
    _envelope(subGain.gain, g * 0.55, 0.06, 0.20, 0.80, 2.0, now);
    subOsc.connect(subGain);
    subGain.connect(_masterGain!);
    subOsc.start(now);
    subOsc.stop(now + 2.5);

    // Fundamental with harmonic waveshaper (soft saturation)
    final osc    = _ctx!.createOscillator();
    final gain   = _gainNode(0);
    final shaper = _ctx!.createWaveShaper();
    shaper.curve = _softSatCurve(256);
    shaper.oversample = '2x';
    osc.type = 'triangle';   // triangle has natural 3rd harmonic
    osc.frequency.value = _freq(pitch);
    _envelope(gain.gain, g * 0.45, 0.04, 0.12, 0.70, 1.8, now);
    osc.connect(gain); gain.connect(shaper); shaper.connect(_masterGain!);
    osc.start(now); osc.stop(now + 2.2);
  }

  /// Soft-clip saturation curve for warm bass harmonics.
  JSFloat32Array _softSatCurve(int samples) {
    final curve = Float32List(samples);
    for (int i = 0; i < samples; i++) {
      final x = (i * 2 / samples) - 1;
      curve[i] = (x * (1.5 - 0.5 * x * x)).clamp(-1.0, 1.0);
    }
    return curve.toJS;
  }

  // ── Voice 1 · String Ensemble Pad ────────────────────────────────────────
  // 4 detuned sawtooth oscillators (±8 cents) for lush HZ string ensemble.
  // Very slow attack (1.5 s) and long release → massive swell.
  void _playPad(int pitch, int velocity) {
    final now = _ctx!.currentTime;
    final g = _gain(velocity, 0.38);

    // Four slightly detuned saws: root & fifth, each ±4 cents
    final configs = [
      (0,  -0.04,  -0.30),   // root - 4 cents, left
      (0,   0.04,  -0.10),   // root + 4 cents, slight left
      (7,  -0.04,   0.10),   // fifth - 4 cents, slight right
      (7,   0.04,   0.30),   // fifth + 4 cents, right
    ];

    final lpf = _filter('lowpass', 900, q: 0.6);
    lpf.connect(_masterGain!);

    for (final (interval, detune, panVal) in configs) {
      final osc  = _ctx!.createOscillator();
      final gain = _gainNode(0);
      final pan  = _panner(panVal);
      osc.type = 'sawtooth';
      osc.frequency.value = _freq(pitch + interval) * (1 + detune / 100);
      // Slow string swell
      _envelope(gain.gain, g * (interval == 0 ? 1.0 : 0.65),
                1.5, 0.30, 0.85, 3.5, now);
      osc.connect(gain); gain.connect(pan); pan.connect(lpf);
      osc.start(now); osc.stop(now + 5.5);
    }
  }

  // ── Voice 2 · Cello Ostinato ──────────────────────────────────────────────
  // Sawtooth + perfect fifth drone + tremolo LFO = bowing string texture.
  void _playCello(int pitch, int velocity) {
    final now = _ctx!.currentTime;
    final g = _gain(velocity, 0.52);

    // Fundamental
    final osc  = _ctx!.createOscillator();
    final gain = _gainNode(0);
    final filt = _filter('lowpass', 1600, q: 1.0);
    final pan  = _panner(-0.30);
    osc.type = 'sawtooth';
    osc.frequency.value = _freq(pitch);

    // Tremolo LFO (rapid bow strokes ~7 Hz)
    final tremoloLFO  = _ctx!.createOscillator();
    final tremoloGain = _gainNode(0.15);   // ±15% amplitude modulation
    tremoloLFO.type = 'sine';
    tremoloLFO.frequency.value = 7.0;
    tremoloLFO.connect(tremoloGain);
    tremoloGain.connect(gain.gain);
    tremoloLFO.start(now);
    tremoloLFO.stop(now + 1.6);

    _envelope(gain.gain, g, 0.07, 0.12, 0.80, 1.2, now);
    osc.connect(gain); gain.connect(filt); filt.connect(pan); pan.connect(_masterGain!);
    osc.start(now); osc.stop(now + 1.6);

    // Quiet perfect fifth layer (cello double-stop)
    final osc5  = _ctx!.createOscillator();
    final gain5 = _gainNode(0);
    osc5.type = 'sawtooth';
    osc5.frequency.value = _freq(pitch + 7);
    _envelope(gain5.gain, g * 0.30, 0.12, 0.10, 0.60, 1.0, now);
    osc5.connect(gain5); gain5.connect(filt);
    osc5.start(now); osc5.stop(now + 1.4);
  }

  // ── Voice 3 · Violin Section ──────────────────────────────────────────────
  // Sawtooth + vibrato LFO, narrower filter for brighter bowing.
  void _playViolin(int pitch, int velocity) {
    final now = _ctx!.currentTime;
    final g = _gain(velocity, 0.44);

    final osc  = _ctx!.createOscillator();
    final gain = _gainNode(0);
    final filt = _filter('bandpass', 2600, q: 2.0);
    final pan  = _panner(0.28);
    osc.type = 'sawtooth';
    osc.frequency.value = _freq(pitch);

    // Vibrato LFO (±6 Hz pitch wobble, 5.5 Hz rate)
    final vib     = _ctx!.createOscillator();
    final vibGain = _gainNode(6.0);
    vib.type = 'sine';
    vib.frequency.value = 5.5;
    vib.connect(vibGain);
    vibGain.connect(osc.frequency);
    vib.start(now + 0.10);   // vibrato enters after onset
    vib.stop(now + 1.3);

    _envelope(gain.gain, g, 0.05, 0.08, 0.82, 1.0, now);
    osc.connect(gain); gain.connect(filt); filt.connect(pan); pan.connect(_masterGain!);
    osc.start(now); osc.stop(now + 1.3);
  }

  // ── Voice 4 · Cinematic Piano ─────────────────────────────────────────────
  // Hans Zimmer's melodic piano: sine fundamental + quick harmonic decay.
  // Long reverb tail (handled by hall reverb in FX chain).
  void _playPiano(int pitch, int velocity) {
    final now = _ctx!.currentTime;
    final g = _gain(velocity, 0.72);

    // Fundamental sine (piano-like purity)
    final osc   = _ctx!.createOscillator();
    final gain  = _gainNode(0);
    final pan   = _panner(0.10);
    osc.type = 'sine';
    osc.frequency.value = _freq(pitch);

    // Piano envelope: instant attack, exponential decay, no sustain
    gain.gain.setValueAtTime(g, now);
    gain.gain.exponentialRampToValueAtTime(g * 0.35, now + 0.12);
    gain.gain.exponentialRampToValueAtTime(0.0001, now + 1.8);   // long tail

    osc.connect(gain); gain.connect(pan); pan.connect(_masterGain!);
    osc.start(now); osc.stop(now + 1.85);

    // 2nd harmonic (subtle brightness)
    final osc2  = _ctx!.createOscillator();
    final gain2 = _gainNode(0);
    osc2.type = 'sine';
    osc2.frequency.value = _freq(pitch + 12);   // octave harmonic
    gain2.gain.setValueAtTime(g * 0.22, now);
    gain2.gain.exponentialRampToValueAtTime(0.0001, now + 0.40);
    osc2.connect(gain2); gain2.connect(pan);
    osc2.start(now); osc2.stop(now + 0.45);

    // 3rd harmonic (adds piano "knock")
    final osc3  = _ctx!.createOscillator();
    final gain3 = _gainNode(0);
    osc3.type = 'sine';
    osc3.frequency.value = _freq(pitch + 19);   // 12 + 7 = 19 st
    gain3.gain.setValueAtTime(g * 0.08, now);
    gain3.gain.exponentialRampToValueAtTime(0.0001, now + 0.18);
    osc3.connect(gain3); gain3.connect(pan);
    osc3.start(now); osc3.stop(now + 0.22);
  }

  // ── Voice 5 · Tick-Tock Ostinato Percussion ──────────────────────────────
  // Inception-style mechanical clock tick: sharp sine transient.
  // Two alternating pitches give the "tock-tick" feel.
  int _tickPhase = 0;
  void _playTick(int pitch, int velocity) {
    final now = _ctx!.currentTime;
    final g = _gain(velocity, 0.40);

    // Alternate between two pitches (tick / tock)
    final tickPitch = _tickPhase.isEven ? pitch : pitch - 5;
    _tickPhase++;

    final osc  = _ctx!.createOscillator();
    final gain = _gainNode(0);
    final pan  = _panner(_tickPhase.isEven ? -0.15 : 0.15);
    osc.type = 'sine';
    osc.frequency.value = _freq(tickPitch);

    // Very sharp transient + instant decay
    gain.gain.setValueAtTime(g, now);
    gain.gain.exponentialRampToValueAtTime(0.0001, now + 0.08);

    osc.connect(gain); gain.connect(pan); pan.connect(_masterGain!);
    osc.start(now); osc.stop(now + 0.10);
  }

  // ── Drone (background pedal tone) ────────────────────────────────────────
  web.GainNode? _droneGain;
  web.OscillatorNode? _droneOsc1;
  web.OscillatorNode? _droneOsc2;
  web.OscillatorNode? _droneOsc3;

  void startDrone(String scale) {
    if (_ctx == null || _masterGain == null) return;
    ensureResumed();
    stopDrone();

    // Map HZ progression names to pedal root
    int root = switch (scale) {
      'inception'    => 45,   // A2
      'interstellar' => 48,   // C3
      'gladiator'    => 50,   // D3
      'minor'        => 45,   // legacy A2
      'phrygian'     => 48,   // legacy C3
      _              => 48,
    };

    final now = _ctx!.currentTime;
    _droneGain = _ctx!.createGain();
    _droneGain!.gain.setValueAtTime(0.0001, now);
    _droneGain!.gain.linearRampToValueAtTime(0.30, now + 7.0);  // slow 7s fade-in

    // Sub-bass sine
    _droneOsc1 = _ctx!.createOscillator();
    _droneOsc1!.type = 'sine';
    _droneOsc1!.frequency.value = _freq(root - 12);   // deep fundamental

    // Detuned triangle (+0.5 Hz) for movement
    _droneOsc2 = _ctx!.createOscillator();
    _droneOsc2!.type = 'triangle';
    _droneOsc2!.frequency.value = _freq(root) + 0.5;

    // Perfect fifth on top (open 5th drone)
    _droneOsc3 = _ctx!.createOscillator();
    _droneOsc3!.type = 'sine';
    _droneOsc3!.frequency.value = _freq(root + 7);

    final lpf = _ctx!.createBiquadFilter();
    lpf.type = 'lowpass';
    lpf.frequency.value = 280;
    lpf.Q.value = 0.5;

    _droneOsc1!.connect(_droneGain!);
    _droneOsc2!.connect(_droneGain!);
    _droneOsc3!.connect(_droneGain!);
    _droneGain!.connect(lpf);
    lpf.connect(_masterGain!);

    _droneOsc1!.start(now);
    _droneOsc2!.start(now);
    _droneOsc3!.start(now);
  }

  void stopDrone() {
    if (_droneGain != null && _ctx != null) {
      final now = _ctx!.currentTime;
      _droneGain!.gain.cancelScheduledValues(now);
      _droneGain!.gain.setValueAtTime(_droneGain!.gain.value, now);
      _droneGain!.gain.linearRampToValueAtTime(0.0001, now + 4.0);

      _droneOsc1?.stop(now + 4.1);
      _droneOsc2?.stop(now + 4.1);
      _droneOsc3?.stop(now + 4.1);

      _droneGain  = null;
      _droneOsc1  = null;
      _droneOsc2  = null;
      _droneOsc3  = null;
    }
  }

  // ── Dispatcher ────────────────────────────────────────────────────────────
  void playVoice(int voice, int pitch, int velocity) {
    if (_ctx == null || _masterGain == null) return;
    ensureResumed();
    switch (voice % 6) {
      case 0: _playBass(pitch, velocity);
      case 1: _playPad(pitch, velocity);
      case 2: _playCello(pitch, velocity);
      case 3: _playViolin(pitch, velocity);
      case 4: _playPiano(pitch, velocity);
      case 5: _playTick(pitch, velocity);
    }
  }
}

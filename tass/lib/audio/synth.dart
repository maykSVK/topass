import 'dart:js_interop';
import 'dart:math';
import 'package:web/web.dart' as web;

class WebAudioSynth {
  web.AudioContext? _ctx;
  web.GainNode? _masterGain;
  web.DelayNode? _delay;
  web.GainNode? _delayFeedback;
  web.GainNode? _delayWet;
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

  void _buildFx() {
    if (_ctx == null) return;
    _masterGain = _ctx!.createGain();
    _masterGain!.gain.value = 0.80;

    _delay = _ctx!.createDelay(2.0);
    _delay!.delayTime.value = 0.24;
    _delayFeedback = _ctx!.createGain();
    _delayFeedback!.gain.value = 0.28;
    _delayWet = _ctx!.createGain();
    _delayWet!.gain.value = 0.25;

    _masterGain!.connect(_ctx!.destination);
    _masterGain!.connect(_delay!);
    _delay!.connect(_delayFeedback!);
    _delayFeedback!.connect(_delay!);
    _delay!.connect(_delayWet!);
    _delayWet!.connect(_ctx!.destination);
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
    param.setValueAtTime(0, now);
    param.linearRampToValueAtTime(gainVal, now + attack);
    param.linearRampToValueAtTime(gainVal * sustain, now + attack + decay);
    param.setValueAtTime(gainVal * sustain, now + attack + decay + 0.05);
    param.exponentialRampToValueAtTime(0.001, now + attack + decay + release);
  }

  void _connectAndPlay(web.OscillatorNode osc, web.AudioNode chain,
      double now, double duration) {
    chain.connect(_masterGain!);
    osc.start(now);
    osc.stop(now + duration + 0.05);
  }

  // ── Voice 0 · Bass Guitar ─────────────────────────────────────────────────
  // Warm sine fundamental + quiet octave → deep, punchy bass
  void _playBass(int pitch, int velocity) {
    final now = _ctx!.currentTime;
    final g = _gain(velocity, 0.75);

    // Fundamental
    final osc  = _ctx!.createOscillator();
    final gain = _gainNode(0);
    final pan  = _panner(-0.05);
    osc.type = 'sine';
    osc.frequency.value = _freq(pitch);
    _envelope(gain.gain, g, 0.01, 0.08, 0.7, 0.9, now);
    osc.connect(gain); gain.connect(pan); pan.connect(_masterGain!);
    osc.start(now); osc.stop(now + 1.1);

    // Subtle octave harmonic
    final osc2  = _ctx!.createOscillator();
    final gain2 = _gainNode(0);
    osc2.type = 'sine';
    osc2.frequency.value = _freq(pitch + 12);
    _envelope(gain2.gain, g * 0.25, 0.02, 0.06, 0.4, 0.6, now);
    osc2.connect(gain2); gain2.connect(pan); // reuse pan node
    osc2.start(now); osc2.stop(now + 0.7);
  }

  // ── Voice 1 · String Pad ──────────────────────────────────────────────────
  // Sawtooth → low-pass filter → slow swell = string ensemble
  void _playPad(int pitch, int velocity) {
    final now = _ctx!.currentTime;
    final g = _gain(velocity, 0.40);

    for (final interval in [0, 7]) {   // root + perfect fifth
      final osc    = _ctx!.createOscillator();
      final gain   = _gainNode(0);
      final filt   = _filter('lowpass', 700, q: 0.8);
      final pan    = _panner(interval == 0 ? -0.15 : 0.15);
      osc.type = 'sawtooth';
      osc.frequency.value = _freq(pitch + interval);
      // Very slow string swell
      _envelope(gain.gain, interval == 0 ? g : g * 0.6,
                0.50, 0.20, 0.80, 2.5, now);
      osc.connect(gain); gain.connect(filt);
      filt.connect(pan); pan.connect(_masterGain!);
      osc.start(now); osc.stop(now + 3.5);
    }
  }

  // ── Voice 2 · Cello ───────────────────────────────────────────────────────
  // Sawtooth → low-pass → slightly brighter than pad, medium attack
  void _playCello(int pitch, int velocity) {
    final now = _ctx!.currentTime;
    final g = _gain(velocity, 0.50);

    final osc  = _ctx!.createOscillator();
    final gain = _gainNode(0);
    final filt = _filter('lowpass', 1400, q: 1.2);
    final pan  = _panner(-0.25);
    osc.type = 'sawtooth';
    osc.frequency.value = _freq(pitch);
    _envelope(gain.gain, g, 0.08, 0.10, 0.75, 1.1, now);
    osc.connect(gain); gain.connect(filt);
    filt.connect(pan); pan.connect(_masterGain!);
    osc.start(now); osc.stop(now + 1.4);
  }

  // ── Voice 3 · Violin ──────────────────────────────────────────────────────
  // Sawtooth → band-pass → brighter, slightly edgy
  void _playViolin(int pitch, int velocity) {
    final now = _ctx!.currentTime;
    final g = _gain(velocity, 0.45);

    final osc  = _ctx!.createOscillator();
    final gain = _gainNode(0);
    final filt = _filter('bandpass', 2200, q: 2.5);
    final pan  = _panner(0.25);
    osc.type = 'sawtooth';
    osc.frequency.value = _freq(pitch);
    _envelope(gain.gain, g, 0.06, 0.08, 0.80, 0.9, now);
    osc.connect(gain); gain.connect(filt);
    filt.connect(pan); pan.connect(_masterGain!);
    osc.start(now); osc.stop(now + 1.1);
  }

  // ── Voice 4 · Flute ───────────────────────────────────────────────────────
  // Sine + LFO vibrato → airy, melodic
  void _playFlute(int pitch, int velocity) {
    final now = _ctx!.currentTime;
    final g = _gain(velocity, 0.65);

    final osc  = _ctx!.createOscillator();
    final gain = _gainNode(0);
    final pan  = _panner(0.20);
    osc.type = 'sine';
    osc.frequency.value = _freq(pitch);

    // Vibrato via LFO on frequency
    final lfo     = _ctx!.createOscillator();
    final lfoGain = _gainNode(3.5);   // ±3.5 Hz pitch wobble
    lfo.type = 'sine';
    lfo.frequency.value = 5.2;        // 5.2 Hz = natural flute vibrato rate
    lfo.connect(lfoGain);
    lfoGain.connect(osc.frequency);
    lfo.start(now + 0.08);            // vibrato starts slightly after note onset
    lfo.stop(now + 0.75);

    _envelope(gain.gain, g, 0.04, 0.05, 0.85, 0.55, now);
    osc.connect(gain); gain.connect(pan); pan.connect(_masterGain!);
    osc.start(now); osc.stop(now + 0.75);
  }

  // ── Voice 5 · Marimba ─────────────────────────────────────────────────────
  // Sine with very fast exponential decay = wooden mallet percussion
  void _playMarimba(int pitch, int velocity) {
    final now = _ctx!.currentTime;
    final g = _gain(velocity, 0.55);

    final osc  = _ctx!.createOscillator();
    final gain = _gainNode(0);
    final pan  = _panner(-0.20);
    osc.type = 'sine';
    osc.frequency.value = _freq(pitch);

    // Pure percussive: instant attack, exponential decay, no sustain
    gain.gain.setValueAtTime(g, now);
    gain.gain.exponentialRampToValueAtTime(0.001, now + 0.55);

    osc.connect(gain); gain.connect(pan); pan.connect(_masterGain!);
    osc.start(now); osc.stop(now + 0.60);
  }

  web.GainNode? _droneGain;
  web.OscillatorNode? _droneOsc1;
  web.OscillatorNode? _droneOsc2;

  void startDrone(String scale) {
    if (_ctx == null || _masterGain == null) return;
    ensureResumed();
    stopDrone();

    int root = 48; // Default C
    if (scale == 'minor') root = 45; // A2
    if (scale == 'phrygian') root = 48; // C3

    final now = _ctx!.currentTime;
    _droneGain = _ctx!.createGain();
    _droneGain!.gain.setValueAtTime(0, now);
    _droneGain!.gain.linearRampToValueAtTime(0.35, now + 5.0); // 5 sec fade-in

    _droneOsc1 = _ctx!.createOscillator();
    _droneOsc1!.type = 'sine';
    _droneOsc1!.frequency.value = _freq(root - 12); // Deep bass

    _droneOsc2 = _ctx!.createOscillator();
    _droneOsc2!.type = 'triangle';
    _droneOsc2!.frequency.value = _freq(root) + 0.3; // Slight detune for phasing/movement

    final lpf = _filter('lowpass', 300, q: 0.5);

    _droneOsc1!.connect(_droneGain!);
    _droneOsc2!.connect(_droneGain!);
    _droneGain!.connect(lpf);
    lpf.connect(_masterGain!);

    _droneOsc1!.start(now);
    _droneOsc2!.start(now);
  }

  void stopDrone() {
    if (_droneGain != null && _ctx != null) {
      final now = _ctx!.currentTime;
      _droneGain!.gain.cancelScheduledValues(now);
      _droneGain!.gain.setValueAtTime(_droneGain!.gain.value, now);
      _droneGain!.gain.linearRampToValueAtTime(0.001, now + 3.0);
      
      _droneOsc1?.stop(now + 3.1);
      _droneOsc2?.stop(now + 3.1);
      
      _droneGain = null;
      _droneOsc1 = null;
      _droneOsc2 = null;
    }
  }

  // ── Dispatcher ───────────────────────────────────────────────────────────
  void playVoice(int voice, int pitch, int velocity) {
    if (_ctx == null || _masterGain == null) return;
    ensureResumed();
    switch (voice % 6) {
      case 0: _playBass(pitch, velocity);
      case 1: _playPad(pitch, velocity);
      case 2: _playCello(pitch, velocity);
      case 3: _playViolin(pitch, velocity);
      case 4: _playFlute(pitch, velocity);
      case 5: _playMarimba(pitch, velocity);
    }
  }
}

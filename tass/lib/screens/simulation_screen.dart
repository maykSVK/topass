import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'dart:convert';
import 'dart:ui' as ui;
import 'dart:typed_data';

import '../main.dart' show themeNotifier;
import '../models/simulation_data.dart';
import '../widgets/visualizer.dart';
import '../audio/synth.dart';

class SimulationScreen extends StatefulWidget {
  const SimulationScreen({Key? key}) : super(key: key);

  @override
  State<SimulationScreen> createState() => _SimulationScreenState();
}

class _SimulationScreenState extends State<SimulationScreen>
    with SingleTickerProviderStateMixin {
  ui.Image? _image;
  SimulationResult? _simulationData;
  bool _isLoading = false;

  late AnimationController _controller;
  int _currentFrame = 0;
  int _maxFrames = 0;

  // ── Audio / playback parameters ──────────────────────────────────────────
  double _durationSeconds = 15.0;
  double _masterVolume    = 0.65;
  double _reverbWet       = 0.42;
  double _delayTime       = 0.11;
  bool   _droneEnabled    = true;
  bool   _settingsOpen    = false;

  final WebAudioSynth _synth = WebAudioSynth();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: Duration(seconds: _durationSeconds.round()));
    _controller.addListener(_onAnimationTick);
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _synth.stopDrone();
        setState(() {});
      }
    });
  }

  void _onAnimationTick() {
    if (_simulationData == null || _maxFrames == 0) return;
    int newFrame = (_controller.value * _maxFrames).floor();
    if (newFrame != _currentFrame) {
      for (var agent in _simulationData!.agents) {
        for (var event in agent.events) {
          if (event.frame > _currentFrame && event.frame <= newFrame) {
            _synth.playVoice(event.voice, event.pitch, event.velocity);
          }
        }
      }
      setState(() => _currentFrame = newFrame);
    }
  }

  Future<void> _uploadImage() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );

    if (result != null && result.files.single.bytes != null) {
      setState(() => _isLoading = true);

      Uint8List fileBytes = result.files.single.bytes!;
      String fileName = result.files.single.name;

      final codec = await ui.instantiateImageCodec(fileBytes);
      final frameInfo = await codec.getNextFrame();

      try {
        var request = http.MultipartRequest(
            'POST', Uri.parse('https://topass-backend-timb.onrender.com/simulate'));
        request.fields['duration'] = _durationSeconds.round().toString();
        request.files.add(http.MultipartFile.fromBytes(
          'image',
          fileBytes,
          filename: fileName,
          contentType: MediaType('image', 'jpeg'),
        ));

        var streamedResponse = await request.send();
        var response = await http.Response.fromStream(streamedResponse);

        if (response.statusCode == 200) {
          final jsonData = json.decode(response.body);
          final simData = SimulationResult.fromJson(jsonData);

          int maxF = 0;
          for (var agent in simData.agents) {
            if (agent.path.length > maxF) maxF = agent.path.length;
          }

          // Fix: honour the current _durationSeconds when computing controller duration
          final tempo = simData.imageStats?.tempoMultiplier ?? 1.0;
          final durationSecs = (_durationSeconds / tempo).clamp(2.0, 120.0).round();

          setState(() {
            _image = frameInfo.image;
            _simulationData = simData;
            _maxFrames = maxF;
            _currentFrame = 0;
            _isLoading = false;
          });
          _controller.duration = Duration(seconds: durationSecs);
        } else {
          // ignore: avoid_print
          print('Backend error: ${response.body}');
          setState(() => _isLoading = false);
        }
      } catch (e) {
        // ignore: avoid_print
        print('Error connecting to backend: $e');
        setState(() => _isLoading = false);
      }
    }
  }

  void _togglePlayback() {
    if (_simulationData == null) return;
    _synth.ensureResumed();

    if (_controller.isAnimating) {
      _controller.stop();
      _synth.stopDrone();
    } else {
      if (_controller.isCompleted) {
        _controller.reset();
        setState(() => _currentFrame = 0);
      }
      _controller.forward();
      if (_droneEnabled) {
        final scale = _simulationData!.imageStats?.scale ?? 'interstellar';
        _synth.startDrone(scale);
      }
    }
    setState(() {});
  }

  /// Called whenever duration slider changes – also updates controller if not animating
  void _onDurationChanged(double val) {
    setState(() => _durationSeconds = val);
    if (!_controller.isAnimating) {
      _controller.duration = Duration(seconds: val.round());
    }
  }

  @override
  void dispose() {
    _synth.stopDrone();
    _controller.dispose();
    super.dispose();
  }

  // ── Mood banner (scale-aware labels) ────────────────────────────────────
  Widget _buildMoodBanner(bool isMobile) {
    if (_simulationData?.imageStats == null) return const SizedBox.shrink();
    final stats = _simulationData!.imageStats!;
    final (icon, mood, desc) = switch (stats.scale) {
      'inception'    => ('✨', 'Inception (Dreamy / Dorian)',      'Bright image → hypnotic Dorian ostinato.'),
      'interstellar' => ('🌌', 'Interstellar (Epic / Aeolian)',    'Mid brightness → open fifths, epic swells.'),
      'gladiator'    => ('⚔️', 'Gladiator (Dark / Phrygian)',     'Dark image → Andalusian cadence, tension.'),
      _              => ('🎵', 'Unknown',                          ''),
    };

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark
        ? const Color(0xFF1A1A24)
        : Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.4);

    final statsWidget = Column(
      crossAxisAlignment: isMobile ? CrossAxisAlignment.start : CrossAxisAlignment.end,
      children: [
        Text('Tempo: ${(stats.tempoMultiplier * 100).round()}%',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13,
                color: isDark ? Colors.white : Colors.black87)),
        const SizedBox(height: 2),
        Text('Edge: ${(stats.edgeDensity * 100).toStringAsFixed(1)}%',
            style: TextStyle(fontSize: 12, color: isDark ? Colors.white54 : Colors.black54)),
      ],
    );

    final textBlock = Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$icon  $mood',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: isMobile ? 13 : 15,
                  color: isDark ? Colors.white : Colors.black87)),
          const SizedBox(height: 3),
          Text(desc,
              style: TextStyle(fontSize: isMobile ? 11 : 13,
                  color: isDark ? Colors.white60 : Colors.black54)),
          if (isMobile) ...[const SizedBox(height: 6), statsWidget],
        ],
      ),
    );

    return Container(
      margin: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 24, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isDark ? Colors.indigo.withOpacity(0.25) : Colors.transparent),
      ),
      padding: EdgeInsets.all(isMobile ? 12 : 16),
      child: Row(
        children: [
          textBlock,
          if (!isMobile) ...[const SizedBox(width: 16), statsWidget],
        ],
      ),
    );
  }

  // ── Settings panel (collapsible) ─────────────────────────────────────────
  Widget _buildSettingsPanel(bool isMobile) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final panelBg = isDark ? const Color(0xFF1A1A2E) : Colors.grey.shade50;
    final labelStyle = TextStyle(
        fontSize: 12, fontWeight: FontWeight.w600,
        color: isDark ? Colors.white70 : Colors.black54);
    final valueStyle = TextStyle(
        fontSize: 12, fontWeight: FontWeight.w700,
        color: isDark ? Colors.white : Colors.black87);

    Widget _row(String label, String value, Widget slider) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        SizedBox(width: isMobile ? 72 : 90,
            child: Text(label, style: labelStyle)),
        Expanded(child: slider),
        SizedBox(width: isMobile ? 42 : 52,
            child: Text(value, style: valueStyle, textAlign: TextAlign.right)),
      ]),
    );

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Duration
        _row(
          'Duration',
          '${_durationSeconds.round()}s',
          Slider(
            value: _durationSeconds, min: 5, max: 60, divisions: 11,
            onChanged: _isLoading ? null : _onDurationChanged,
          ),
        ),
        // Master volume
        _row(
          'Volume',
          '${(_masterVolume * 100).round()}%',
          Slider(
            value: _masterVolume, min: 0.0, max: 1.0, divisions: 20,
            onChanged: (v) {
              setState(() => _masterVolume = v);
              _synth.setMasterVolume(v);
            },
          ),
        ),
        // Reverb
        _row(
          'Reverb',
          '${(_reverbWet * 100).round()}%',
          Slider(
            value: _reverbWet, min: 0.0, max: 1.0, divisions: 20,
            onChanged: (v) {
              setState(() => _reverbWet = v);
              _synth.setReverbWet(v);
            },
          ),
        ),
        // Delay
        _row(
          'Delay',
          '${(_delayTime * 1000).round()}ms',
          Slider(
            value: _delayTime, min: 0.0, max: 0.5, divisions: 25,
            onChanged: (v) {
              setState(() => _delayTime = v);
              _synth.setDelayTime(v);
            },
          ),
        ),
        // Drone toggle
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(children: [
            SizedBox(width: isMobile ? 72 : 90,
                child: Text('Drone', style: labelStyle)),
            Switch(
              value: _droneEnabled,
              onChanged: (v) {
                setState(() => _droneEnabled = v);
                if (!v) _synth.stopDrone();
              },
            ),
            const SizedBox(width: 8),
            Text(_droneEnabled ? 'On' : 'Off', style: valueStyle),
          ]),
        ),
      ],
    );

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      margin: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 24),
      decoration: BoxDecoration(
        color: panelBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? Colors.indigo.withOpacity(0.2) : Colors.grey.shade200,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header / toggle row
          InkWell(
            onTap: () => setState(() => _settingsOpen = !_settingsOpen),
            child: Padding(
              padding: EdgeInsets.symmetric(
                  horizontal: isMobile ? 14 : 18, vertical: isMobile ? 10 : 12),
              child: Row(children: [
                Icon(Icons.tune_rounded, size: 18,
                    color: isDark ? Colors.white60 : Colors.black54),
                const SizedBox(width: 8),
                Text('Sound Settings',
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white70 : Colors.black87)),
                const Spacer(),
                AnimatedRotation(
                  turns: _settingsOpen ? 0.5 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(Icons.expand_more_rounded, size: 20,
                      color: isDark ? Colors.white38 : Colors.black38),
                ),
              ]),
            ),
          ),
          // Expandable body
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: EdgeInsets.fromLTRB(
                  isMobile ? 8 : 14, 0, isMobile ? 8 : 14, isMobile ? 8 : 12),
              child: content,
            ),
            crossFadeState: _settingsOpen
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }

  // ── AppBar ───────────────────────────────────────────────────────────────
  PreferredSizeWidget _buildAppBar(bool isMobile, bool isDark) {
    final logo = ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Transform.scale(
        scale: 1.35,
        alignment: const Alignment(0, -0.2),
        child: Image.network('logo.jpg',
            fit: BoxFit.cover,
            width: isMobile ? 44 : 64,
            height: isMobile ? 44 : 64,
            errorBuilder: (c, e, s) => const Icon(Icons.music_note, size: 28)),
      ),
    );

    final title = isMobile
        ? Text('TASS',
            style: TextStyle(
                fontSize: 20, fontWeight: FontWeight.w900,
                color: Theme.of(context).colorScheme.primary))
        : RichText(
            text: TextSpan(children: [
              TextSpan(text: 'Top',
                  style: TextStyle(color: Theme.of(context).colorScheme.primary,
                      fontSize: 22, fontWeight: FontWeight.w900)),
              TextSpan(text: 'ographic ',
                  style: TextStyle(color: isDark ? Colors.white60 : Colors.black54,
                      fontSize: 17, fontWeight: FontWeight.w300)),
              TextSpan(text: 'A',
                  style: TextStyle(color: Theme.of(context).colorScheme.primary,
                      fontSize: 22, fontWeight: FontWeight.w900)),
              TextSpan(text: 'gents ',
                  style: TextStyle(color: isDark ? Colors.white60 : Colors.black54,
                      fontSize: 17, fontWeight: FontWeight.w300)),
              TextSpan(text: 'S',
                  style: TextStyle(color: Theme.of(context).colorScheme.primary,
                      fontSize: 22, fontWeight: FontWeight.w900)),
              TextSpan(text: 'onification ',
                  style: TextStyle(color: isDark ? Colors.white60 : Colors.black54,
                      fontSize: 17, fontWeight: FontWeight.w300)),
              TextSpan(text: 'S',
                  style: TextStyle(color: Theme.of(context).colorScheme.primary,
                      fontSize: 22, fontWeight: FontWeight.w900)),
              TextSpan(text: 'ystem',
                  style: TextStyle(color: isDark ? Colors.white60 : Colors.black54,
                      fontSize: 17, fontWeight: FontWeight.w300)),
            ]),
          );

    final themeBtn = IconButton(
      icon: Icon(isDark ? Icons.light_mode : Icons.dark_mode, size: 20),
      onPressed: () => themeNotifier.value = isDark ? ThemeMode.light : ThemeMode.dark,
      tooltip: 'Toggle Theme',
    );

    final uploadBtn = isMobile
        ? IconButton(
            icon: const Icon(Icons.upload_file_rounded, size: 22),
            onPressed: _isLoading ? null : _uploadImage,
            tooltip: 'Upload image',
          )
        : ElevatedButton.icon(
            onPressed: _isLoading ? null : _uploadImage,
            icon: const Icon(Icons.upload_file_rounded, size: 17),
            label: const Text('Upload'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
          );

    final playBtn = _simulationData == null
        ? null
        : isMobile
            ? IconButton(
                icon: Icon(
                    _controller.isAnimating
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    size: 26),
                onPressed: _togglePlayback,
              )
            : ElevatedButton.icon(
                onPressed: _togglePlayback,
                icon: Icon(
                    _controller.isAnimating
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    size: 17),
                label: Text(_controller.isAnimating ? 'Pause' : 'Play'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
              );

    return AppBar(
      toolbarHeight: isMobile ? 56 : 72,
      title: Row(children: [
        logo,
        const SizedBox(width: 10),
        title,
      ]),
      actions: [
        uploadBtn,
        if (playBtn != null) playBtn,
        themeBtn,
        SizedBox(width: isMobile ? 4 : 8),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenW = MediaQuery.of(context).size.width;
    final isMobile = screenW < 600;
    final hPad = isMobile ? 12.0 : 24.0;

    return Scaffold(
      appBar: _buildAppBar(isMobile, isDark),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Mood banner
          _buildMoodBanner(isMobile),

          // Settings panel
          _buildSettingsPanel(isMobile),

          const SizedBox(height: 8),

          // Loading indicator
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Column(children: [
                CircularProgressIndicator(),
                SizedBox(height: 12),
                Text('Analyzing topographic data…',
                    style: TextStyle(color: Colors.grey, fontSize: 13)),
              ]),
            ),

          // Visualizer canvas
          Expanded(
            child: Padding(
              padding: EdgeInsets.fromLTRB(hPad, 8, hPad, hPad),
              child: Container(
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF15151E) : Colors.white,
                  borderRadius: BorderRadius.circular(isMobile ? 14 : 20),
                  border: isDark
                      ? Border.all(color: Colors.indigo.withOpacity(0.1))
                      : null,
                  boxShadow: [
                    if (!isDark)
                      BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 20,
                          offset: const Offset(0, 6)),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: _image == null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.image_search_rounded,
                                size: isMobile ? 48 : 64,
                                color: isDark ? Colors.white24 : Colors.black12),
                            const SizedBox(height: 12),
                            Text('Upload an image to begin',
                                style: TextStyle(
                                    fontSize: isMobile ? 14 : 16,
                                    color: isDark ? Colors.white38 : Colors.black38)),
                          ],
                        ),
                      )
                    : Visualizer(
                        image: _image,
                        simulationData: _simulationData,
                        currentFrame: _currentFrame,
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

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
  double _durationSeconds = 15.0; // Default duration

  final WebAudioSynth _synth = WebAudioSynth();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(seconds: 15));
    _controller.addListener(_onAnimationTick);
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

      setState(() {
        _currentFrame = newFrame;
      });
    }
  }

  Future<void> _uploadImage() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );

    if (result != null && result.files.single.bytes != null) {
      setState(() {
        _isLoading = true;
      });

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
            if (agent.path.length > maxF) {
              maxF = agent.path.length;
            }
          }

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
          print("Backend error: ${response.body}");
          setState(() => _isLoading = false);
        }
      } catch (e) {
        // ignore: avoid_print
        print("Error connecting to backend: $e");
        setState(() => _isLoading = false);
      }
    }
  }

  void _togglePlayback() {
    if (_simulationData == null) return;

    _synth.ensureResumed();

    if (_controller.isAnimating) {
      _controller.stop();
    } else {
      if (_controller.isCompleted) {
        _controller.reset();
        setState(() => _currentFrame = 0);
      }
      _controller.forward();
    }
    setState(() {});
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _buildMoodBanner() {
    if (_simulationData == null || _simulationData!.imageStats == null) {
      return const SizedBox.shrink();
    }
    final stats = _simulationData!.imageStats!;
    String icon = '';
    String mood = '';
    String desc = '';

    switch (stats.scale) {
      case 'lydian':
        icon = '☀️';
        mood = 'Lydian (Bright / Open)';
        desc = 'High brightness signature detected. Harmonizing in major.';
        break;
      case 'phrygian':
        icon = '🌑';
        mood = 'Phrygian (Dark / Tense)';
        desc = 'Low brightness signature detected. Harmonizing with tension.';
        break;
      case 'minor':
      default:
        icon = '🌙';
        mood = 'Minor (Melancholic / Flowing)';
        desc = 'Mid-range brightness signature. Harmonizing in natural minor.';
        break;
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1A24) : Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? Colors.indigo.withOpacity(0.3) : Colors.transparent),
      ),
      padding: const EdgeInsets.all(20.0),
      child: Row(
        children: [
          Text(icon, style: const TextStyle(fontSize: 40)),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Sonic Profile: $mood', 
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: isDark ? Colors.white : Colors.black87)),
                const SizedBox(height: 4),
                Text(desc, 
                  style: TextStyle(color: isDark ? Colors.white70 : Colors.black87.withOpacity(0.7), fontSize: 14)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF232332) : Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                if (!isDark) BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))
              ]
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                 Text('Tempo: ${(stats.tempoMultiplier * 100).round()}%', 
                   style: TextStyle(fontWeight: FontWeight.w600, color: isDark ? Colors.white : Colors.black87)),
                 const SizedBox(height: 2),
                 Text('Edge Density: ${(stats.edgeDensity * 100).toStringAsFixed(1)}%', 
                   style: TextStyle(fontSize: 12, color: isDark ? Colors.white54 : Colors.black54)),
              ]
            )
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 85,
        title: Row(
          children: [
            Container(
              height: 64,
              width: 100,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  )
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Transform.scale(
                  scale: 1.35,
                  alignment: const Alignment(0, -0.2), // Shift slightly to ensure bottom text is fully visible
                  child: Image.network('logo.jpg', fit: BoxFit.cover, errorBuilder: (c,e,s) => const Icon(Icons.music_note, size: 32)),
                ),
              ),
            ),
            const SizedBox(width: 20),
            RichText(
              text: TextSpan(
                children: [
                  TextSpan(text: 'Top', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 26, fontWeight: FontWeight.w900)),
                  TextSpan(text: 'ographic ', style: TextStyle(color: isDark ? Colors.white60 : Colors.black54, fontSize: 20, fontWeight: FontWeight.w300)),
                  TextSpan(text: 'A', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 26, fontWeight: FontWeight.w900)),
                  TextSpan(text: 'gents ', style: TextStyle(color: isDark ? Colors.white60 : Colors.black54, fontSize: 20, fontWeight: FontWeight.w300)),
                  TextSpan(text: 'S', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 26, fontWeight: FontWeight.w900)),
                  TextSpan(text: 'onification ', style: TextStyle(color: isDark ? Colors.white60 : Colors.black54, fontSize: 20, fontWeight: FontWeight.w300)),
                  TextSpan(text: 'S', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 26, fontWeight: FontWeight.w900)),
                  TextSpan(text: 'ystem', style: TextStyle(color: isDark ? Colors.white60 : Colors.black54, fontSize: 20, fontWeight: FontWeight.w300)),
                ],
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton.icon(
            onPressed: _isLoading ? null : _uploadImage,
            icon: const Icon(Icons.upload_file_rounded, size: 18),
            label: const Text('Upload'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
          const SizedBox(width: 12),
          if (_simulationData != null) ...[
            ElevatedButton.icon(
              onPressed: _togglePlayback,
              icon: Icon(_controller.isAnimating ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 18),
              label: Text(_controller.isAnimating ? 'Pause' : 'Play'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
            const SizedBox(width: 12),
          ],
          IconButton(
            icon: Icon(isDark ? Icons.light_mode : Icons.dark_mode),
            onPressed: () {
              themeNotifier.value = isDark ? ThemeMode.light : ThemeMode.dark;
            },
            tooltip: 'Toggle Theme',
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Column(
        children: [
          _buildMoodBanner(),
          
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 0.0),
            child: Row(
              children: [
                Text('Duration: ${_durationSeconds.round()}s', style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87)),
                Expanded(
                  child: Slider(
                    value: _durationSeconds,
                    min: 5,
                    max: 60,
                    divisions: 11, // 5, 10, 15, ..., 60
                    label: '${_durationSeconds.round()}s',
                    onChanged: _isLoading ? null : (val) {
                      setState(() {
                        _durationSeconds = val;
                      });
                    },
                  ),
                ),
              ],
            ),
          ),

          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(24.0),
              child: Column(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Analyzing topographic data...', style: TextStyle(color: Colors.grey)),
                ],
              ),
            ),
            
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
              child: Container(
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF15151E) : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: isDark ? Border.all(color: Colors.indigo.withOpacity(0.1)) : null,
                  boxShadow: [
                    if (!isDark) BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 24, offset: const Offset(0, 8))
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Visualizer(
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

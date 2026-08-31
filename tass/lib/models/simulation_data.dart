class ImageStats {
  final String scale;
  final double meanBrightness;
  final double stdBrightness;
  final double edgeDensity;
  final double tempoMultiplier;
  final double timbreHint;

  ImageStats({
    required this.scale,
    required this.meanBrightness,
    required this.stdBrightness,
    required this.edgeDensity,
    required this.tempoMultiplier,
    required this.timbreHint,
  });

  factory ImageStats.fromJson(Map<String, dynamic> json) {
    return ImageStats(
      scale: json['scale'] as String,
      meanBrightness: (json['mean_brightness'] as num).toDouble(),
      stdBrightness: (json['std_brightness'] as num).toDouble(),
      edgeDensity: (json['edge_density'] as num).toDouble(),
      tempoMultiplier: (json['tempo_multiplier'] as num).toDouble(),
      timbreHint: (json['timbre_hint'] as num).toDouble(),
    );
  }
}

class PathPoint {
  final double x;
  final double y;

  PathPoint({required this.x, required this.y});

  factory PathPoint.fromJson(Map<String, dynamic> json) {
    return PathPoint(
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
    );
  }
}

class NoteEvent {
  final int frame;
  final int pitch;
  final int velocity;
  final int z;
  /// Voice role: 0=bass, 1=pad, 2=inner_low, 3=inner_high, 4=melody, 5=ornament
  final int voice;

  NoteEvent({
    required this.frame,
    required this.pitch,
    required this.velocity,
    required this.z,
    required this.voice,
  });

  factory NoteEvent.fromJson(Map<String, dynamic> json) {
    return NoteEvent(
      frame: json['frame'] as int,
      pitch: json['pitch'] as int,
      velocity: json['velocity'] as int,
      z: json['z'] as int,
      voice: (json['voice'] as int?) ?? 4,
    );
  }
}

class AgentData {
  final int id;
  final List<PathPoint> path;
  final List<NoteEvent> events;
  final double mass;

  AgentData({
    required this.id,
    required this.path,
    required this.events,
    required this.mass,
  });

  factory AgentData.fromJson(Map<String, dynamic> json) {
    return AgentData(
      id: json['id'] as int,
      path: (json['path'] as List).map((e) => PathPoint.fromJson(e)).toList(),
      events:
          (json['events'] as List).map((e) => NoteEvent.fromJson(e)).toList(),
      mass: (json['mass'] as num).toDouble(),
    );
  }
}

class SimulationResult {
  final int width;
  final int height;
  final List<AgentData> agents;
  final ImageStats? imageStats;

  SimulationResult({
    required this.width,
    required this.height,
    required this.agents,
    this.imageStats,
  });

  factory SimulationResult.fromJson(Map<String, dynamic> json) {
    return SimulationResult(
      width: json['width'] as int,
      height: json['height'] as int,
      agents:
          (json['agents'] as List).map((e) => AgentData.fromJson(e)).toList(),
      imageStats: json['image_stats'] != null
          ? ImageStats.fromJson(json['image_stats'])
          : null,
    );
  }
}

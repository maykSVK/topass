import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import '../models/simulation_data.dart';

class Visualizer extends StatelessWidget {
  final ui.Image? image;
  final SimulationResult? simulationData;
  final int currentFrame;

  const Visualizer({
    Key? key,
    this.image,
    this.simulationData,
    required this.currentFrame,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (image == null) {
      return const Center(
        child: Text(
          'Upload an image to begin',
          style: TextStyle(
            color: Colors.black45,
            fontSize: 16,
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        double scaleX = constraints.maxWidth / image!.width;
        double scaleY = constraints.maxHeight / image!.height;
        double scale = scaleX < scaleY ? scaleX : scaleY;

        return Center(
          child: SizedBox(
            width: image!.width * scale,
            height: image!.height * scale,
            child: CustomPaint(
              painter: SimulationPainter(
                image: image!,
                simulationData: simulationData,
                currentFrame: currentFrame,
                scale: scale,
                primaryColor: Theme.of(context).colorScheme.primary,
              ),
              size: Size(image!.width * scale, image!.height * scale),
            ),
          ),
        );
      },
    );
  }
}

class SimulationPainter extends CustomPainter {
  final ui.Image image;
  final SimulationResult? simulationData;
  final int currentFrame;
  final double scale;
  final Color primaryColor;

  SimulationPainter({
    required this.image,
    this.simulationData,
    required this.currentFrame,
    required this.scale,
    required this.primaryColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Draw the background image naturally, no sci-fi tint
    final Rect srcRect = Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    final Rect dstRect = Rect.fromLTWH(0, 0, size.width, size.height);
    
    // We can add a very subtle opacity to the image so the agents stand out more cleanly
    final Paint imagePaint = Paint()..color = Colors.white.withOpacity(0.9);
    canvas.drawImageRect(image, srcRect, dstRect, imagePaint);

    if (simulationData == null) return;

    // 2. Clean, modern agents and paths
    final Paint pathPaint = Paint()
      ..color = primaryColor.withOpacity(0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final Paint agentPaint = Paint()
      ..color = primaryColor
      ..style = PaintingStyle.fill;
      
    final Paint agentOutlinePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    for (var agent in simulationData!.agents) {
      if (currentFrame > 0 && agent.path.isNotEmpty) {
        Path path = Path();
        int endFrame = currentFrame < agent.path.length ? currentFrame : agent.path.length - 1;
        
        path.moveTo(agent.path[0].x * scale, agent.path[0].y * scale);
        for (int i = 1; i <= endFrame; i++) {
          path.lineTo(agent.path[i].x * scale, agent.path[i].y * scale);
        }
        canvas.drawPath(path, pathPaint);
      }

      int frameIdx = currentFrame < agent.path.length ? currentFrame : (agent.path.isNotEmpty ? agent.path.length - 1 : -1);
      
      if (frameIdx >= 0) {
        final pos = agent.path[frameIdx];
        final offset = Offset(pos.x * scale, pos.y * scale);
        
        // Solid modern dot with a clean white outline
        canvas.drawCircle(offset, 5.0, agentPaint);
        canvas.drawCircle(offset, 5.0, agentOutlinePaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant SimulationPainter oldDelegate) {
    return oldDelegate.currentFrame != currentFrame || oldDelegate.image != image;
  }
}

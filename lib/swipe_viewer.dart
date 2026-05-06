import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_upload_app/core/services/image_service.dart';

class SwipeViewer extends StatefulWidget {
  final List<String> images;
  final int initialIndex;

  const SwipeViewer({
    super.key,
    required this.images,
    required this.initialIndex,
  });

  @override
  State<SwipeViewer> createState() => _SwipeViewerState();
}

class _SwipeViewerState extends State<SwipeViewer> {
  late PageController controller;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
    controller = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: PageView.builder(
        controller: controller,
        itemCount: widget.images.length,
        itemBuilder: (context, index) {
          return buildZoomableImage(widget.images[index]);
        },
      ),
    );
  }
}

Widget buildZoomableImage(String path) {
  return FutureBuilder<String>(
    future: getImageUrl(path),
    builder: (context, snapshot) {
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator(strokeWidth: 2));
      }

      return InteractiveViewer(
        minScale: 1,
        maxScale: 4,
        child: Center(
          child: Image.network(
            snapshot.data!,
            fit: BoxFit.contain,
            width: double.infinity,
            height: double.infinity,
            errorBuilder: (_, __, ___) =>
                const Icon(Icons.broken_image, color: Colors.white),
          ),
        ),
      );
    },
  );
}

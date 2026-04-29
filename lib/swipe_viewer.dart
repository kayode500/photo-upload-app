import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:flutter/material.dart';
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
  double scale = 1.0;

  @override
  void initState() {
    super.initState();
    controller = PageController(initialPage: widget.initialIndex,    viewportFraction: 0.92, // 🔥 adds spacing effect
    );
    
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
  backgroundColor: Colors.black,
  body: PageView.builder(
    controller: controller,
    physics: const BouncingScrollPhysics(), // ✅ ALWAYS allow swipe
    itemCount: widget.images.length,
    itemBuilder: (context, index) {
      final image = widget.images[index];

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Center(
          child: _ZoomableImage(image: image),
        ),
      );
    },
  ),
);

  }
}

class _ZoomableImage extends StatefulWidget {
  final String image;

  const _ZoomableImage({required this.image});

  @override
  State<_ZoomableImage> createState() => _ZoomableImageState();
}

class _ZoomableImageState extends State<_ZoomableImage> {
  double scale = 1.0;

  @override
Widget build(BuildContext context) {
  return GestureDetector(
    onDoubleTap: () {
      setState(() {
        scale = scale == 1 ? 2.5 : 1;
      });
    },
    child: InteractiveViewer(
      panEnabled: scale > 1, // ✅ only pan when zoomed
      minScale: 1,
      maxScale: 4,
      boundaryMargin: const EdgeInsets.all(20),
      child: AnimatedScale(
        duration: const Duration(milliseconds: 200),
        scale: scale,
        child: SizedBox.expand(
          child: FutureBuilder<String>(
            future: Amplify.Storage.getUrl(
              path: StoragePath.fromString(widget.image), // 🔥 now using PATH
            ).result.then((r) => r.url.toString()),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(
                  child: CircularProgressIndicator(),
                );
              }

              return Image.network(
                snapshot.data!,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return const Center(
                    child: Icon(Icons.broken_image, color: Colors.grey),
                  );
                },
              );
            },
          ),
        ),
      ),
    ),
  );
}
}
import 'package:amplify_flutter/amplify_flutter.dart';

final Map<String, String> signedUrlCache = {};
final Map<String, Future<String>> pendingRequests = {};

String normalizePath(String path) {
  return path.trim();
}

Future<String> getImageUrl(String path) async {
  final key = normalizePath(path);

  // ✅ cached
  if (signedUrlCache.containsKey(key)) {
    return signedUrlCache[key]!;
  }

  // 🔥 prevent duplicate calls
  if (pendingRequests.containsKey(key)) {
    return pendingRequests[key]!;
  }

  final future = Amplify.Storage.getUrl(path: StoragePath.fromString(key))
      .result
      .then((result) {
        final url = result.url.toString();

        signedUrlCache[key] = url;
        pendingRequests.remove(key);

        if (signedUrlCache.length > 100) {
          signedUrlCache.remove(signedUrlCache.keys.first);
        }

        return url;
      });

  pendingRequests[key] = future;

  return future;
}

void preloadImages(List<String> paths) {
  for (final path in paths.take(10)) {
    getImageUrl(path);
  }
}

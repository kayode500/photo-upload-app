import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import 'auth/auth_ screen.dart';
import 'package:share_plus/share_plus.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:image_gallery_saver/image_gallery_saver.dart';
//import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'swipe_viewer.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ImagePicker _picker = ImagePicker();
  int currentIndex = 0;
  bool isDeleting = false;
  double uploadProgress = 0;
  bool isUploading = false;
  Map<String, String> favoriteMap = {};
  List<String> imageUrls = [];
  List<String> imagePaths = [];
  List<String> allPaths = []; // 🔥 ALL fetched paths
  bool isFetchingMore = false;
  final int pageSize = 20;
  // List<String> favoritePaths = [];
  bool isLoading = false;
  String status = "";
  int currentLimit = 20;
  final Map<String, String> signedUrlCache = {};
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      //    await clearAllFavorites();
      await loadCloudFavorites();
      await fetchImages();
      _scrollController.addListener(() {
        if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200) {
          loadMoreImages();
        }
      });
    });
  }

  // 📸 Pick Image
  Future<void> pickImage() async {
    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.gallery);

      if (image == null) return;

      final file = File(image.path);

      await uploadToS3(file, image.name);
    } catch (e) {
      print("Pick image error: $e");
    }
  }

  Future<String> getUserId() async {
    final user = await Amplify.Auth.getCurrentUser();
    return user.userId;
  }

  // ☁️ Upload
  Future<void> uploadToS3(File file, String name) async {
    final identityId = await getIdentityId();

    setState(() {
      isUploading = true;
      uploadProgress = 0;
    });

    try {
      final uploadOperation = Amplify.Storage.uploadFile(
        localFile: AWSFile.fromPath(file.path),
        path: StoragePath.fromString("private/$identityId/uploads/$name"),
        onProgress: (progress) {
          setState(() {
            uploadProgress = progress.transferredBytes / progress.totalBytes;
          });
        },
      );

      await uploadOperation.result;

      await fetchImages();

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Upload successful")));
    } catch (e) {
      print("Upload error: $e");

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Upload failed")));
    }

    setState(() {
      isUploading = false;
    });
  }

  Future<String> getIdentityId() async {
    final session = await Amplify.Auth.fetchAuthSession();

    if (session is CognitoAuthSession) {
      final result = session.identityIdResult;

      return result.value;
    } else {
      throw Exception("Not a Cognito session");
    }
  }

  Future<void> fetchImages() async {
    setState(() {
      isLoading = true;
    });

    try {
      final identityId = await getIdentityId();

      final listResult = await Amplify.Storage.list(
        path: StoragePath.fromString("private/$identityId/uploads/"),
      ).result;

      allPaths = listResult.items.map((e) => e.path).toList();

      // 🔥 clear current UI state for fresh load
      imageUrls.clear();
      imagePaths.clear();

      // 🔥 use cached URLs if available first
      for (final path in allPaths) {
        try {
          String url;

          if (signedUrlCache.containsKey(path)) {
            url = signedUrlCache[path]!; // ⚡ cached
          } else {
            final urlResult = await Amplify.Storage.getUrl(
              path: StoragePath.fromString(path),
            ).result;

            url = urlResult.url.toString();

            signedUrlCache[path] = url; // 🔥 cache it
          }

          imageUrls.add(url);
          imagePaths.add(path);
        } catch (e) {
          print("❌ URL error for $path: $e");
        }
      }

      setState(() {});
    } catch (e) {
      print("❌ ERROR: $e");
      setState(() {
        status = "❌ Error loading images: $e";
      });
    }

    setState(() {
      isLoading = false;
    });
  }

  Future<void> loadMoreImages({bool reset = false}) async {
    if (isFetchingMore) return;
    // final int pageSize = 5;

    isFetchingMore = true;

    try {
      if (reset) {
        imageUrls.clear();
        imagePaths.clear();
        currentLimit = pageSize;
      } else {
        currentLimit += pageSize;
      }

      final pathsToLoad = allPaths
          .take(currentLimit)
          .skip(imagePaths.length)
          .toList();

      for (final path in pathsToLoad) {
        try {
          final urlResult = await Amplify.Storage.getUrl(
            path: StoragePath.fromString(path),
          ).result;

          imageUrls.add(urlResult.url.toString());
          imagePaths.add(path);
          signedUrlCache[path] = urlResult.url.toString();
        } catch (e) {
          print("❌ URL error: $e");
        }
      }
      // print("📦 Loaded batch:");
      // print("Current visible: ${imageUrls.length}");
      // print("Total paths: ${allPaths.length}");

      setState(() {});
    } catch (e) {
      print("❌ Pagination error: $e");
    }

    isFetchingMore = false;
  }

  Future<void> deleteImage(String input) async {
    final key = _normalizePath(extractPath(input)); // 🔥 identity

    // 🔥 find original storage path
    final originalPath = imagePaths.firstWhere(
      (p) => _normalizePath(p) == key,
      orElse: () => key,
    );

    final favoriteId = favoriteMap[key];

    try {
      // ✅ delete from S3
      await Amplify.Storage.remove(
        path: StoragePath.fromString(originalPath),
      ).result;

      // ✅ delete from favorites (if exists)
      if (favoriteId != null) {
        await Amplify.API
            .mutate(
              request: GraphQLRequest<String>(
                document:
                    '''
            mutation DeleteFavorite {
              deleteFavorite(input: { id: "$favoriteId" }) {
                id
              }
            }
            ''',
              ),
            )
            .response;
      }

      setState(() {
        for (var i = imagePaths.length - 1; i >= 0; i--) {
          if (_normalizePath(imagePaths[i]) == key) {
            imagePaths.removeAt(i);
            if (i < imageUrls.length) {
              imageUrls.removeAt(i);
            }
          }
        }

        allPaths.removeWhere((p) => _normalizePath(p) == key);
        favoriteMap.remove(key);
        signedUrlCache.remove(key);
        if (currentLimit > imagePaths.length) {
          currentLimit = imagePaths.length;
        }
      });

      print("✅ Image deleted");
    } catch (e) {
      print("❌ Delete error: $e");
    }
  }

  // }
  Future<String> getImageUrl(String path) async {
    final key = _normalizePath(path);

    // ✅ return cached URL instantly
    if (signedUrlCache.containsKey(key)) {
      return signedUrlCache[key]!;
    }

    try {
      final result = await Amplify.Storage.getUrl(
        path: StoragePath.fromString(key),
      ).result;

      final url = result.url.toString();

      // ✅ store in cache
      signedUrlCache[key] = url;

      // ✅ prevent memory overflow
      if (signedUrlCache.length > 100) {
        signedUrlCache.clear();
      }

      return url;
    } catch (e) {
      print("❌ getImageUrl error: $e");
      rethrow;
    }
  }

  String extractPath(String fullUrl) {
    final uri = Uri.parse(fullUrl);
    final segments = uri.pathSegments;

    // private/<identityId>/uploads/image.png
    final index = segments.indexOf('private');
    if (index < 0) {
      return uri.path.startsWith('/') ? uri.path.substring(1) : uri.path;
    }

    return segments.sublist(index).join('/');
  }

  Future<void> confirmDelete(String path) async {
    final confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Image"),
        content: const Text("Are you sure you want to delete this image?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Delete"),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await deleteImage(path);
    }
  }

  Future<void> logout() async {
    try {
      await Amplify.Auth.signOut();
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const AuthScreen()),
      );
      print("✅ Logged out successfully");
    } catch (e) {
      print("❌ Logout error: $e");
    }
  }

  Future<void> clearAllFavorites() async {
    try {
      String? nextToken;

      do {
        final request = GraphQLRequest<String>(
          document: '''
        query ListFavorites(\$nextToken: String) {
          listFavorites(nextToken: \$nextToken) {
            items {
              id
            }
            nextToken
          }
        }
        ''',
          variables: {"nextToken": nextToken},
        );

        final response = await Amplify.API.query(request: request).response;

        final data = jsonDecode(response.data!);
        final result = data['listFavorites'];

        final items = result['items'];
        nextToken = result['nextToken'];

        for (var item in items) {
          final id = item['id'];

          await Amplify.API
              .mutate(
                request: GraphQLRequest<String>(
                  document:
                      '''
            mutation DeleteFavorite {
              deleteFavorite(input: { id: "$id" }) {
                id
              }
            }
            ''',
                ),
              )
              .response;

          print("🗑 Deleted: $id");
        }
      } while (nextToken != null);

      setState(() {
        favoriteMap.clear();
      });

      print("✅ ALL favorites cleared from DB");
    } catch (e) {
      print("❌ Error clearing favorites: $e");
    }
  }

  Future<void> toggleFavorite(String input) async {
    final key = _normalizePath(extractPath(input)); // 🔥 ALWAYS SAFE

    final isFav = favoriteMap.containsKey(key);

    if (isFav) {
      final id = favoriteMap[key];

      try {
        await Amplify.API
            .mutate(
              request: GraphQLRequest<String>(
                document:
                    '''
          mutation DeleteFavorite {
            deleteFavorite(input: { id: "$id" }) {
              id
            }
          }
          ''',
              ),
            )
            .response;

        setState(() {
          favoriteMap.remove(key);
        });
      } catch (e) {
        print("❌ Remove favorite error: $e");
      }
    } else {
      try {
        final response = await Amplify.API
            .mutate(
              request: GraphQLRequest<String>(
                document:
                    '''
          mutation CreateFavorite {
            createFavorite(input: { imageUrl: "$key" }) {
              id
              imageUrl
            }
          }
          ''',
              ),
            )
            .response;

        final data = jsonDecode(response.data!);
        final newItem = data['createFavorite'];

        setState(() {
          favoriteMap[key] = newItem['id'];
        });
      } catch (e) {
        print("❌ Add favorite error: $e");
      }
    }
  }

  Future<void> loadCloudFavorites() async {
    final request = GraphQLRequest<String>(
      document: '''
    query ListFavorites {
      listFavorites {
        items {
          id
          imageUrl
        }
      }
    }
    ''',
    );

    final response = await Amplify.API.query(request: request).response;

    if (response.data == null) {
      print("❌ No response data");
      return;
    }

    final data = jsonDecode(response.data!);

    final List items = data['listFavorites']?['items'] ?? []; // 🔥 SAFE

    final Map<String, String> tempMap = {};
    // final List<String> tempPaths = [];

    for (var item in items) {
      if (item == null) continue;

      final url = item['path'] ?? item['imageUrl']; // 🔥 support both fields
      final id = item['id'];

      if (url == null || id == null) continue; // 🔥 safety check

      final key = _normalizePath(extractPath(url)); // 🔥 FIX

      tempMap[key] = id;
      //tempPaths.add(key);
    }

    setState(() {
      favoriteMap = tempMap;
      // favoritePaths = favoriteMap.keys.toList();
    });

    //print("✅ Favorites synced: ${favoriteMap.length}");
  }

  Future<void> shareImage(String path) async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Preparing image..."),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.black87,
          duration: Duration(seconds: 2),
        ),
      );

      final signedUrl = await getImageUrl(path);

      // 🔥 DOWNLOAD IMAGE
      final response = await http.get(Uri.parse(signedUrl));

      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/shared_image.png');

      await file.writeAsBytes(response.bodyBytes);

      // 🔥 SHARE FILE (NOT LINK)
      await Share.shareXFiles([
        XFile(file.path),
      ], text: "Check out this image!");
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Failed to share image")));

      print("❌ Share error: $e");
    }
  }

  Future<void> downloadImage(String path) async {
    try {
      // 🔥 REQUEST PERMISSION FIRST
      final status = await Permission.photos.request();

      if (!status.isGranted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Permission denied"),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.black87,
            duration: Duration(seconds: 2),
          ),
        );
        return;
      }

      final signedUrl = await getImageUrl(path);
      final response = await http.get(Uri.parse(signedUrl));

      final result = await ImageGallerySaver.saveImage(
        response.bodyBytes,
        quality: 100,
        name: "downloaded_image",
      );

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Image saved to gallery"),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.black87,
          duration: const Duration(seconds: 2),
        ),
      );

      print("✅ Saved: $result");
    } catch (e) {
      print("❌ Download error: $e");
    }
  }

  String _normalizePath(String url) {
    final uri = Uri.parse(url);
    return uri.path.startsWith('/') ? uri.path.substring(1) : uri.path;
  }

  Widget buildImageItem(int index) {
    final path = imagePaths[index];
    final key = _normalizePath(path);

    return GestureDetector(
      onTap: () async {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                SwipeViewer(images: imagePaths, initialIndex: index),
          ),
        );
      },
      onLongPress: () {
        confirmDelete(path);
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Stack(
          children: [
            // 🖼 IMAGE
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Hero(
                  tag: imagePaths[index], // 🔥 use PATH as tag now
                  child: FutureBuilder<String>(
                    future: getSignedUrl(
                      imagePaths[index],
                    ), // 🔥 use PATH to get URL
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return Container(
                          color: Colors.grey[200],
                          child: Center(child: loadingWidget()),
                        );
                      }

                      return Image.network(
                        snapshot.data!,
                        fit: BoxFit.cover,
                        filterQuality: FilterQuality.low,
                        loadingBuilder: (context, child, progress) {
                          if (progress == null) return child;
                          return Container(
                            color: Colors.grey[200],
                            child: const Center(
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          );
                        },
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            color: Colors.grey[300],
                            child: const Center(
                              child: Icon(
                                Icons.broken_image,
                                color: Colors.grey,
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ),
            ),

            // ❤️ FAVORITE (TOP RIGHT)
            Positioned(
              top: 8,
              right: 8,
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => toggleFavorite(path),
                child: CircleAvatar(
                  radius: 16,
                  backgroundColor: Colors.black.withOpacity(0.4),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    transitionBuilder: (child, animation) {
                      return ScaleTransition(scale: animation, child: child);
                    },
                    child: Icon(
                      favoriteMap.containsKey(key)
                          ? Icons.favorite
                          : Icons.favorite_border,
                      key: ValueKey(favoriteMap.containsKey(key)),
                      color: Colors.redAccent,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ),

            // 🔗 SHARE (BOTTOM RIGHT)
            Positioned(
              bottom: 8,
              right: 8,
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => shareImage(path),
                child: CircleAvatar(
                  radius: 16,
                  backgroundColor: Colors.black.withOpacity(0.4),
                  child: const Icon(Icons.share, color: Colors.white, size: 18),
                ),
              ),
            ),

            // 📥 DOWNLOAD (BOTTOM LEFT)
            Positioned(
              bottom: 8,
              left: 8,
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => downloadImage(path),
                child: CircleAvatar(
                  radius: 16,
                  backgroundColor: Colors.black.withOpacity(0.4),
                  child: const Icon(
                    Icons.download,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<String> getSignedUrl(String path) async {
    // ✅ return cached if exists
    if (signedUrlCache.containsKey(path)) {
      return signedUrlCache[path]!;
    }

    // 🔄 fetch new signed URL
    final result = await Amplify.Storage.getUrl(
      path: StoragePath.fromString(path),
    ).result;

    final url = result.url.toString();

    // 💾 store in cache
    signedUrlCache[path] = url;

    // 🚨 LIMIT CACHE SIZE (PUT IT HERE)
    if (signedUrlCache.length > 100) {
      signedUrlCache.clear();
    }

    return url;
  }

  Widget buildFavoritesGrid() {
    final favoritePaths = favoriteMap.keys
        .map((e) => _normalizePath(e))
        .toList();
    if (favoritePaths.isEmpty) {
      return const Center(child: Text("No favorites yet"));
    }

    return GridView.builder(
      cacheExtent: 1000,
      padding: const EdgeInsets.all(10),
      controller: _scrollController,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 5,
        mainAxisSpacing: 5,
      ),
      itemCount: favoritePaths.length,
      itemBuilder: (context, index) {
        final rawPath = favoritePaths[index];
        final path = _normalizePath(rawPath);
        return FutureBuilder<String>(
          key: ValueKey(path),
          future: getImageUrl(path),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return loadingWidget();
            }

            final imageUrl = snapshot.data!;

            return GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SwipeViewer(
                      images: favoritePaths, // 🔥 use favorite list
                      initialIndex: index,
                    ),
                  ),
                );
              },
              onLongPress: () {
                confirmDelete(path);
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        filterQuality: FilterQuality.low,
                        loadingBuilder: (context, child, loadingProgress) =>
                            loadingProgress == null
                            ? child
                            : Container(
                                color: Colors.grey[300],
                                child: Center(child: loadingWidget()),
                              ),
                      ),
                    ),
                    Positioned(
                      top: 5,
                      right: 5,
                      child: GestureDetector(
                        onTap: () => toggleFavorite(path),
                        child: CircleAvatar(
                          radius: 14,
                          backgroundColor: Colors.black54,
                          child: Icon(
                            favoriteMap.containsKey(path)
                                ? Icons.favorite
                                : Icons.favorite_border,
                            color: Colors.red,
                            size: 18,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text(
          "My Gallery",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        actions: [
          IconButton(icon: const Icon(Icons.logout), onPressed: logout),
        ],
      ),

      // 👇 BODY SWITCHES BETWEEN TABS
      body: getCurrentScreen(),

      // 👇 BOTTOM NAVIGATION
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: currentIndex,
        onTap: (index) {
          setState(() {
            currentIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.photo), label: "Gallery"),
          BottomNavigationBarItem(
            icon: Icon(Icons.favorite),
            label: "Favorites",
          ),
        ],
      ),

      // 👇 FAB ONLY ON GALLERY
      floatingActionButton: currentIndex == 0
          ? FloatingActionButton(
              backgroundColor: Colors.black,
              onPressed: isUploading ? null : pickImage,
              child: isUploading
                  ? loadingWidget()
                  : const Icon(Icons.add, color: Colors.white),
            )
          : null,
    );
  }

  Widget getCurrentScreen() {
    if (currentIndex == 0) {
      // 🖼 GALLERY TAB

      if (isLoading) {
        return loadingWidget();
      }

      if (imageUrls.isEmpty) {
        return RefreshIndicator(
          onRefresh: fetchImages,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: const [SizedBox(height: 200), EmptyState()],
          ),
        );
      }

      return RefreshIndicator(
        onRefresh: fetchImages,
        child: GridView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(12),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemCount: imageUrls.length,
          itemBuilder: (context, index) {
            return buildImageItem(index);
          },
        ),
      );
    } else {
      // ❤️ FAVORITES TAB
      return buildFavoritesGrid();
    }
  }
}

Widget loadingWidget() {
  return const Center(child: CircularProgressIndicator(strokeWidth: 2));
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.photo_library_outlined, size: 80, color: Colors.grey),
          SizedBox(height: 16),
          Text(
            "No images yet",
            style: TextStyle(fontSize: 18, color: Colors.grey),
          ),
          SizedBox(height: 8),
          Text(
            "Tap the + button to add your first photo",
            style: TextStyle(fontSize: 14, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}

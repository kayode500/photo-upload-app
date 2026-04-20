import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import 'preview_screen.dart';
import 'auth/auth_ screen.dart';
import 'package:share_plus/share_plus.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

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
  // key = normalized path, value = favoriteId
  Map<String, String> pathToUrl = {};

  List<String> imageUrls = [];
  List<String> imagePaths = [];
  bool isLoading = false;
  String status = "";

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      // await clearAllFavorites();
      await loadCloudFavorites();
      await fetchImages();
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

  // 🖼 Fetch images
  Future<void> fetchImages() async {
    setState(() {
      isLoading = true;
    });

    try {
      final identityId = await getIdentityId();

      final listResult = await Amplify.Storage.list(
        path: StoragePath.fromString("private/$identityId/uploads/"),
      ).result;

      List<String> urls = [];
      List<String> paths = [];

      for (final item in listResult.items) {
        try {
          final urlResult = await Amplify.Storage.getUrl(
            path: StoragePath.fromString(item.path),
          ).result;

          urls.add(urlResult.url.toString());
          paths.add(item.path);
          pathToUrl[item.path] = urlResult.url.toString();
        } catch (urlError) {
          print("❌ Error getting URL for ${item.path}: $urlError");
        }
      }

      setState(() {
        imageUrls = urls;
        imagePaths = paths;
      });
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

  Future<void> deleteImage(String path) async {
    setState(() {
      isDeleting = true;
    });

    try {
      await Amplify.Storage.remove(path: StoragePath.fromString(path)).result;

      await fetchImages();

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Image deleted")));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error deleting image")));
    }

    setState(() {
      isDeleting = false;
    });
  }

  Future<String> getImageUrl(String path) async {
    final result = await Amplify.Storage.getUrl(
      path: StoragePath.fromString(path),
    ).result;

    return result.url.toString();
  }

  String extractPath(String fullUrl) {
    final uri = Uri.parse(fullUrl);
    final segments = uri.pathSegments;

    // private/<identityId>/uploads/image.png
    final index = segments.indexOf('private');

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

  Future<void> toggleFavorite(String url) async {
    final key = _normalizePath(url);
    final isFav = favoriteMap.containsKey(key);

    if (isFav) {
      // REMOVE
      final id = favoriteMap[key];

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
        pathToUrl.remove(key);
      });
    } else {
      // ADD

      // 🔥 HARD GUARD (PREVENT DUPLICATE)
      if (favoriteMap.containsKey(key)) return;

      final response = await Amplify.API
          .mutate(
            request: GraphQLRequest<String>(
              document:
                  '''
          mutation CreateFavorite {
            createFavorite(input: { imageUrl: "$url" }) {
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
        pathToUrl[key] = url;
      });
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

    final data = jsonDecode(response.data!);
    final items = data['listFavorites']['items'];

    final Map<String, String> tempMap = {};

    for (var item in items) {
      final url = item['imageUrl'];
      final id = item['id'];
      final key = _normalizePath(url);

      // 🔥 PREVENT DUPLICATES HERE
      tempMap[key] = id;
      pathToUrl[key] = url;
    }

    // 🔥 IMPORTANT: SINGLE SETSTATE ONLY
    setState(() {
      favoriteMap = tempMap;
    });

    print("✅ Favorites synced: ${favoriteMap.length}");
  }

  Future<void> shareImage(String imageUrl) async {
    try {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Preparing image...")));

      final signedUrl = await getImageUrl(extractPath(imageUrl));

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

  String _normalizePath(String url) {
    final uri = Uri.parse(url);
    return uri.path.startsWith('/') ? uri.path.substring(1) : uri.path;
  }

  Widget buildImageItem(int index) {
    final imageUrl = imageUrls[index];
    final key = _normalizePath(imageUrl);

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => PreviewScreen(url: imageUrl)),
        );
      },
      onLongPress: () {
        confirmDelete(imagePaths[index]);
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 6,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned.fill(child: Image.network(imageUrl, fit: BoxFit.cover)),

            Positioned(
              top: 5,
              right: 5,
              child: GestureDetector(
                onTap: () => toggleFavorite(imageUrl),
                child: CircleAvatar(
                  radius: 14,
                  backgroundColor: Colors.black54,
                  child: Icon(
                    favoriteMap.containsKey(key)
                        ? Icons.favorite
                        : Icons.favorite_border,
                    color: Colors.red,
                    size: 18,
                  ),
                ),
              ),
            ),
            Positioned(
              top: 5,
              left: 5,
              child: GestureDetector(
                onTap: () => shareImage(imageUrl),
                child: CircleAvatar(
                  radius: 14,
                  backgroundColor: Colors.black54,
                  child: Icon(Icons.share, color: Colors.white, size: 18),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildFavoritesGrid() {
    final favoriteUrls = favoriteMap.keys.toList();

    if (favoriteUrls.isEmpty) {
      return const Center(child: Text("No favorites yet"));
    }

    return GridView.builder(
      padding: const EdgeInsets.all(10),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 5,
        mainAxisSpacing: 5,
      ),
      itemCount: favoriteUrls.length,
      itemBuilder: (context, index) {
        final path = favoriteUrls[index];

        return FutureBuilder<String>(
          future: getImageUrl(path),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final imageUrl = snapshot.data!;

            return GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PreviewScreen(url: imageUrl),
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
                      child: Image.network(imageUrl, fit: BoxFit.cover,
                      loadingBuilder: (context, child, loadingProgress) => loadingProgress == null
                          ? child
                          : Container(
                              color: Colors.grey[300],
                              child: const Center(
                                child: CircularProgressIndicator(),
                              ),
                            ),
                      ),
                    ),
                    Positioned(
                      top: 5,
                      right: 5,
                      child: GestureDetector(
                        onTap: () => toggleFavorite(imageUrl),
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
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Icon(Icons.add, color: Colors.white),
            )
          : null,
    );
  }

  Widget getCurrentScreen() {
    if (currentIndex == 0) {
      // 🖼 GALLERY TAB

      if (isLoading) {
        return const Center(child: CircularProgressIndicator());
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

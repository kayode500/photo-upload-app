import 'dart:io';

import 'package:flutter/material.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import 'preview_screen.dart';
import 'auth/auth_ screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  Set<String> favoriteImages = {};

  List<String> imageUrls = [];
  List<String> imagePaths = [];
  bool isLoading = false;
  String status = "";

  @override
  @override
  void initState() {
    super.initState();
    loadCloudFavorites();
    fetchImages();
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

  Future<void> loadFavorites() async {
    final prefs = await SharedPreferences.getInstance();

    final saved = prefs.getStringList('favorites');

    if (saved != null) {
      setState(() {
        favoriteImages = saved.toSet();
      });
    }
  }

  Future<void> toggleFavorite(String url) async {
  final isFav = favoriteImages.contains(url);

  setState(() {
    if (isFav) {
      favoriteImages.remove(url);
    } else {
      favoriteImages.add(url);
    }
  });

  try {
    if (!isFav) {
      // ➕ ADD FAVORITE
      final request = GraphQLRequest<String>(
        document: '''
        mutation CreateFavorite {
          createFavorite(input: { imageUrl: "$url" }) {
            id
          }
        }
        ''',
      );

      await Amplify.API.mutate(request: request).response;
    } else {
      // ❌ REMOVE FAVORITE

      // 1️⃣ Find the favorite first
      final query = GraphQLRequest<String>(
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

      final response = await Amplify.API.query(request: query).response;

      final data = response.data;

      if (data != null) {
        final match = RegExp(
          r'\{[^}]*"id":"(.*?)"[^}]*"imageUrl":"$url"[^}]*\}',
        ).firstMatch(data);

        if (match != null) {
          final favId = match.group(1);

          final deleteRequest = GraphQLRequest<String>(
            document: '''
            mutation DeleteFavorite {
              deleteFavorite(input: { id: "$favId" }) {
                id
              }
            }
            ''',
          );

          await Amplify.API.mutate(request: deleteRequest).response;
        }
      }
    }
  } catch (e) {
    print("Cloud favorite error: $e");
  }
}
Future<void> loadCloudFavorites() async {
  try {
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

    final data = response.data;

    if (data != null) {
      final urls = RegExp(r'"imageUrl":"(.*?)"')
          .allMatches(data)
          .map((m) => m.group(1)!)
          .toSet();

      setState(() {
        favoriteImages = urls;
      });
    }
  } catch (e) {
    print("Error loading favorites: $e");
  }
}
  Widget buildImageItem(int index) {
  final imageUrl = imageUrls[index];
  final isFavorite = favoriteImages.contains(imageUrl);

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
          )
        ],
      ),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.network(
              imageUrl,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
            ),
          ),

          // 🔥 GRADIENT OVERLAY
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withOpacity(0.3),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // ❤️ FAVORITE ICON
          Positioned(
            top: 8,
            right: 8,
            child: GestureDetector(
              onTap: () => toggleFavorite(imageUrl),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isFavorite
                      ? Icons.favorite
                      : Icons.favorite_border,
                  color: isFavorite ? Colors.red : Colors.white,
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

  Widget buildFavoritesGrid() {
    final favList = imageUrls
        .where((url) => favoriteImages.contains(url))
        .toList();

    if (favList.isEmpty) {
      return const Center(child: Text("No favorites yet"));
    }

    return GridView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(10),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 5,
        mainAxisSpacing: 5,
      ),
      itemCount: favList.length,
      itemBuilder: (context, index) {
        final imageUrl = favList[index];

        return GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => PreviewScreen(url: imageUrl)),
            );
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(imageUrl, fit: BoxFit.cover),
          ),
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
    IconButton(
      icon: const Icon(Icons.logout),
      onPressed: logout,
    ),
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

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import 'preview_screen.dart';
import 'auth/auth_ screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ImagePicker _picker = ImagePicker();
  bool isDeleting = false;
  double uploadProgress = 0;
  bool isUploading = false;

  List<String> imageUrls = [];
  List<String> imagePaths = [];
  bool isLoading = false;
  String status = "";

  @override
  void initState() {
    super.initState();
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

  Widget buildImageItem(int index) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PreviewScreen(url: imageUrls[index]),
          ),
        );
      },
      onLongPress: isDeleting ? null : () => confirmDelete(imagePaths[index]),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(imageUrls[index], fit: BoxFit.cover),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("My Gallery"),
        actions: [
          IconButton(icon: const Icon(Icons.logout), onPressed: logout),
        ],
      ),

      floatingActionButton: FloatingActionButton(
        onPressed: isUploading ? null : pickImage,
        child: const Icon(Icons.add),
      ),

      body: isUploading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text("Uploading... ${(uploadProgress * 100).toInt()}%"),
                  const SizedBox(height: 16),
                  LinearProgressIndicator(value: uploadProgress),
                ],
              ),
            )
          : isLoading
          ? const Center(child: CircularProgressIndicator())
          : imageUrls.isEmpty
          ? const EmptyState()
          : GridView.builder(
              padding: const EdgeInsets.all(10),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 5,
                mainAxisSpacing: 5,
              ),
              itemCount: imageUrls.length,
              itemBuilder: (context, index) {
                return buildImageItem(index);
              },
            ),
    );
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

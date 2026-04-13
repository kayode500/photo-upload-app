import 'package:flutter/material.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import 'package:amplify_storage_s3/amplify_storage_s3.dart';

import 'amplifyconfiguration.dart';
import 'auth/auth_ screen.dart';
import 'home_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool isAmplifyReady = false;

  @override
  void initState() {
    super.initState();
    configureAmplify();
  }

  Future<void> configureAmplify() async {
    try {
      await Amplify.addPlugins([
        AmplifyAuthCognito(),
        AmplifyStorageS3(),
      ]);

      await Amplify.configure(amplifyconfig);

      setState(() {
        isAmplifyReady = true;
      });
    } catch (e) {
      print("Amplify error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,

      // ⏳ Wait until Amplify is ready
      home: isAmplifyReady
          ? const AuthScreen()
          : const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            ),

      routes: {
        "/home": (context) => const HomeScreen(),
      },
    );
  }
}
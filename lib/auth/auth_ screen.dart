
import 'package:flutter/material.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:photo_upload_app/home_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool isLogin = true;

  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  String status = "";

  Future<void> signUp() async {
  try {
    final result = await Amplify.Auth.signUp(
      username: emailController.text.trim(),
      password: passwordController.text.trim(),
      options: SignUpOptions(
        userAttributes: {
          AuthUserAttributeKey.email: emailController.text.trim(),
        },
      ),
    );

    if (result.isSignUpComplete) {
      setState(() {
        status = "✅ Signup complete. Please login.";
      });
    } else {
      setState(() {
        status = "📩 Enter the OTP sent to your email";
      });

      showOTPDialog(); // 👈 ADD THIS
    }
  } catch (e) {
    setState(() {
      status = "❌ Signup error: $e";
    });
  }
}
void showOTPDialog() {
  final codeController = TextEditingController();

  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text("Enter OTP"),
      content: TextField(
        controller: codeController,
        decoration: const InputDecoration(hintText: "Enter code"),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await confirmSignUp(codeController.text.trim());
            Navigator.pop(context);
          },
          child: const Text("Confirm"),
        ),
      ],
    ),
  );
}

Future<void> confirmSignUp(String code) async {
  try {
    await Amplify.Auth.confirmSignUp(
      username: emailController.text.trim(),
      confirmationCode: code,
    );

    setState(() {
      status = "✅ Account confirmed! Now login.";
      isLogin = true;
    });
  } catch (e) {
    setState(() {
      status = "❌ Confirmation error: $e";
    });
  }
}

  Future<void> signIn() async {
  try {
    final result = await Amplify.Auth.signIn(
      username: emailController.text.trim(),
      password: passwordController.text.trim(),
    );

    print("LOGIN RESULT: ${result.isSignedIn}");

    if (result.isSignedIn) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const HomeScreen())
      );
    } else {
      setState(() {
        status = "❌ Login not complete";
      });
    }
  } catch (e) {
    setState(() {
      status = "❌ Login error: $e";
    });
  }
  final user = await Amplify.Auth.getCurrentUser();
  print("USER: ${user.userId}");
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(isLogin ? "Login" : "Sign Up"),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: emailController,
              decoration: const InputDecoration(labelText: "Email"),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: passwordController,
              obscureText: true,
              decoration: const InputDecoration(labelText: "Password"),
            ),
            const SizedBox(height: 20),

            ElevatedButton(
              onPressed: isLogin ? signIn : signUp,
              child: Text(isLogin ? "Login" : "Sign Up"),
            ),

            TextButton(
              onPressed: () {
                setState(() {
                  isLogin = !isLogin;
                });
              },
              child: Text(
                isLogin
                    ? "Don't have an account? Sign Up"
                    : "Already have an account? Login",
              ),
            ),

            const SizedBox(height: 20),
            Text(status),
          ],
        ),
      ),
    );
  }
}
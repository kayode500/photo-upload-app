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
  bool isLoading = false;
  bool? isPasswordHidden = true;

  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  String status = "";

  Future<void> signUp() async {
    // 🔥 Basic validation
    if (emailController.text.trim().isEmpty ||
        passwordController.text.trim().isEmpty) {
      setState(() {
        status = "Please fill all fields";
      });
      return;
    }

    setState(() {
      isLoading = true;
      status = "";
    });

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

        showOTPDialog(); // ✅ keep your OTP flow
      }
    } catch (e) {
      final msg = getAuthErrorMessage(e); // 🔥 CLEAN ERROR

      setState(() {
        status = msg;
      });

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }

    setState(() {
      isLoading = false;
    });
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
    // 🔥 Basic validation
    if (emailController.text.trim().isEmpty ||
        passwordController.text.trim().isEmpty) {
      setState(() {
        status = "Please enter email and password";
      });
      return;
    }

    setState(() {
      isLoading = true;
      status = "";
    });

    try {
      final result = await Amplify.Auth.signIn(
        username: emailController.text.trim(),
        password: passwordController.text.trim(),
      );

      if (result.isSignedIn) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Login successful")));
        // ✅ Navigate to home
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const HomeScreen()),
        );
      } else {
        setState(() {
          status = "Login not complete. Please try again.";
        });
      }
    } catch (e) {
      final msg = getAuthErrorMessage(e); // 🔥 CLEAN ERROR

      setState(() {
        status = msg;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }

    setState(() {
      isLoading = false;
    });
  }

  String getAuthErrorMessage(dynamic error) {
    final message = error.toString();

    if (message.contains("UserNotFoundException")) {
      return "User not found. Please sign up.";
    } else if (message.contains("NotAuthorizedException")) {
      return "Incorrect email or password.";
    } else if (message.contains("UserNotConfirmedException")) {
      return "Please verify your email before logging in.";
    } else if (message.contains("UsernameExistsException")) {
      return "Account already exists. Please login.";
    } else if (message.contains("InvalidPasswordException")) {
      return "Password must be stronger.";
    } else if (message.contains("NetworkException")) {
      return "Check your internet connection.";
    } else {
      return "Something went wrong. Try again.";
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text(isLogin ? "Login" : "Sign Up"),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              "Welcome Back",
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: emailController,
              decoration: InputDecoration(
                hintText: "Email",
                hintStyle: TextStyle(color: Colors.grey[600]),
                prefixIcon: Icon(Icons.email_outlined, color: Colors.grey[600]),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.black),
                ),
              ),
              style: const TextStyle(color: Colors.black),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: passwordController,
              obscureText: isPasswordHidden ?? true,
              decoration: InputDecoration(
                hintText: "Password",
                hintStyle: TextStyle(color: Colors.grey[600]),
                prefixIcon: Icon(Icons.lock_outline, color: Colors.grey[600]),
                suffixIcon: IconButton(
                  icon: Icon(
                    (isPasswordHidden ?? true)
                        ? Icons.visibility_off
                        : Icons.visibility,
                    color: Colors.grey[600],
                  ),
                  onPressed: () {
                    setState(() {
                      isPasswordHidden = !(isPasswordHidden ?? true);
                    });
                  },
                ),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.black),
                ),
              ),
              style: const TextStyle(color: Colors.black),
            ),
            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: isLoading ? null : (isLogin ? signIn : signUp),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text(
                        isLogin ? "Login" : "Sign Up",
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.white,
                        ),
                      ),
              ),
            ),

            if (status.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  status,
                  style: TextStyle(
                    color: status.contains("❌") ? Colors.red : Colors.green,
                    fontWeight: FontWeight.w500,
                  ),
                ),
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
                style: const TextStyle(color: Colors.black87),
              ),
            ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

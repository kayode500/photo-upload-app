# 🚀 Private Cloud Gallery App

A Flutter mobile app that allows users to upload, view, favorite, and manage private images securely using AWS Amplify.

---

## ✨ Features

- 📤 Upload images to secure cloud storage (S3)
- 🖼️ Smooth grid gallery
- ❤️ Favorite system with cloud sync (GraphQL)
- 🔍 Swipe viewer with zoom & gestures
- 🗑️ Delete images with confirmation
- ⚡ Cached signed URLs for fast performance

---

## 🧠 Architecture

- **Frontend:** Flutter
- **Storage:** AWS Amplify S3
- **API:** GraphQL
- **State Management:** Local state with normalized path identity

---

## 🔥 Key Challenges Solved

- Eliminated duplicate favorites using consistent path identity
- Fixed gesture conflicts (tap vs long press)
- Optimized image loading with caching
- Maintained sync between gallery and favorites after login/logout

---

## 📱 Screens

- Gallery View
- Favorites View
- Swipe Viewer

---

## ⚙️ Setup

1. Clone the repo
2. Run:
   ```bash
   flutter pub get
   ```

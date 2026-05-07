# 📸 Photo Upload App

A modern Flutter-based photo management app that allows users to upload, view, favorite, share, and download images seamlessly with cloud storage integration.

---

## 🚀 Features

- 🔐 Secure authentication (Sign up / Sign in)
- 📤 Upload images to cloud storage
- 🖼️ Gallery view with smooth grid layout
- ❤️ Favorite / Unfavorite images
- 🔍 Full-screen swipe image viewer
- 📤 Share images to other apps (WhatsApp, etc.)
- 💾 Download images to device gallery
- ⚡ Optimized image loading with caching
- 📱 Smooth UI with tab navigation (no flicker)

---

## 🧠 Tech Stack

- Flutter
- Dart
- AWS Amplify (Auth + Storage)
- GraphQL API
- HTTP package
- Share Plus
- Permission Handler

---

## 📸 Screenshots

### 🔐 Login Screen

![Login](./assets/screenshots/login.jpeg)

### 🖼️ Gallery View

![Gallery](./assets/screenshots/gallery_v2.jpeg)

### ❤️ Favorites

![Favorites](./assets/screenshots/favorite.jpeg)

### 🔍 Image Viewer

![Viewer](./assets/screenshots/viewer.jpeg)

---

## ⚙️ Architecture Highlights

- Centralized image URL caching (performance optimization)
- IndexedStack for smooth tab switching (no flicker)
- Session persistence with Amplify Auth
- Clean separation of UI and services

---

## 📦 Installation

```bash
git clone https://github.com/yourusername/photo-upload-app.git
cd photo-upload-app
flutter pub get
flutter run
```

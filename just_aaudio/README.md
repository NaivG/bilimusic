# just_aaudio

A Flutter plugin providing low-latency audio playback on Android using AAudio/Oboe, with seamless fallback to just_audio.

## Features

- **Low-latency playback** via AAudio/Oboe native audio stack
- **Format support** via libsndfile: WAV, AIFF, and other standard formats
- **Automatic conversion** for compressed formats (MP3, M4A, AAC, OGG, etc.)
- **Unified API** compatible with just_audio
- **Hot-swap** between AAudio and just_audio backends at runtime

## Architecture

```
lib/
├── just_aaudio.dart          # Main plugin entry
├── players/
│   ├── audio.dart            # AudioPlayer (switches between backends)
│   └── aaudio.dart           # AAudio Dart-side wrapper
└── models/
    └── adapter.dart          # AudioPlayerAdapter interface

android/
├── java/.../
│   ├── JustAaudioFlutterPlugin.java   # Flutter plugin registration
│   └── AAudioPlayer.java              # Java AAudio bridge
└── cpp/
    └── native-audio.cpp               # C++ Oboe audio engine
```

### Key Components

- **AudioPlayer** — Main class that wraps either `JustAudioAdapter` or `AAudioPlayer` via `AudioPlayerAdapter`
- **AAudioPlayer** — Dart FFI bridge to native AAudio engine
- **AudioEngine** (C++) — Oboe-based audio renderer with resampling, volume, speed control

## Usage

```dart
import 'package:just_aaudio/just_aaudio.dart';

// Create player
final player = AudioPlayer();

// Use like just_audio
await player.setFilePath('/path/to/audio.wav');
await player.play();

// Switch to AAudio backend for low latency
await player.setPlayerType(PlayerType.aaudio);

// Or use just_audio backend for broad format support
await player.setPlayerType(PlayerType.justAudio);
```

## Building

```bash
flutter pub get
flutter build apk
```

## Requirements

- Flutter >= 3.0
- Android API 21+ (Oboe requires Android 8.0+)
- NDK for native compilation (included in Flutter Android toolchain)
# OkHttp Platform classes
-dontwarn org.conscrypt.**
-dontwarn org.openjsse.**

# Keep Conscrypt classes if they are referenced
-keep class org.conscrypt.** { *; }
-keep class org.openjsse.** { *; }

# OkHttp platform classes
-keep class okhttp3.internal.platform.** { *; }
-keep class okhttp3.internal.http2.** { *; }

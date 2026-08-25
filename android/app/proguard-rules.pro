# Flutter & Android ProGuard Rules

# OkHttp & Security provider warnings
-dontwarn org.bouncycastle.jsse.**
-dontwarn org.conscrypt.**
-dontwarn org.openjsse.**
-dontwarn okhttp3.internal.platform.**
-dontwarn okhttp3.**

# Flutter Rust Bridge & JNI bindings
-keep class com.notetosms.app.** { *; }

# Keep annotations and reflection attributes
-keepattributes *Annotation*,Signature,InnerClasses,EnclosingMethod

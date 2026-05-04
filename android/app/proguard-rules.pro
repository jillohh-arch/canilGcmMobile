# =====================================================================
# Regras ProGuard/R8 para o app GCM K9
# Evita que o R8 ofusque/remova classes críticas do Firebase e libs de imagem
# =====================================================================

# --- Firebase Core ---
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# --- Firebase Auth ---
-keep class com.google.firebase.auth.** { *; }

# --- Firebase Firestore ---
-keep class com.google.firebase.firestore.** { *; }

# --- Firebase Storage ---
-keep class com.google.firebase.storage.** { *; }

# --- Firebase App Check ---
-keep class com.google.firebase.appcheck.** { *; }
-dontwarn com.google.firebase.appcheck.**

# --- Glide (usado internamente pelo cached_network_image) ---
-keep public class * implements com.bumptech.glide.module.GlideModule
-keep class * extends com.bumptech.glide.module.AppGlideModule { <init>(...); }
-keep public enum com.bumptech.glide.load.ImageHeaderParser$** {
  **[] $VALUES;
  public *;
}
-dontwarn com.bumptech.glide.**

# --- OkHttp (rede) ---
-dontwarn okhttp3.**
-dontwarn okio.**
-keep class okhttp3.** { *; }
-keep interface okhttp3.** { *; }

# --- Flutter ---
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.**

# --- Modelos de dados (evita que sejam removidos pela reflexão) ---
-keep class com.example.canil_gcm.** { *; }

# Preserva anotações de serialização
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes SourceFile,LineNumberTable

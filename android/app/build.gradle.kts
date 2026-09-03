plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

android {
    namespace = "com.example.canil_gcm"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.canil_gcm"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    // Alvos Firebase explícitos por flavor.
    //
    // `production` mantém o applicationId histórico e resolve
    // `android/app/google-services.json` (canil-gcm). `staging` acrescenta o
    // sufixo `.staging`, o que faz o plugin Google Services resolver
    // `android/app/src/staging/google-services.json` (k9-ops-staging).
    //
    // applicationIds distintos permitem que os dois APKs coexistam no mesmo
    // aparelho — homologação nunca sobrescreve produção.
    flavorDimensions += "environment"

    productFlavors {
        create("production") {
            dimension = "environment"
            // Sem suffix: applicationId permanece com.example.canil_gcm.
        }
        create("staging") {
            dimension = "environment"
            applicationIdSuffix = ".staging"
            versionNameSuffix = "-stg"
            // O rótulo visível vem do source-set `src/staging/res`, que
            // sobrepõe `src/main/res` — não de `resValue`, para não duplicar
            // recurso com o `strings.xml` de main.
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            // Minificação ativada com regras ProGuard explícitas para proteger Firebase/Storage
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("androidx.multidex:multidex:2.0.1")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

import java.io.File
import java.io.Reader
import java.util.Properties

fun File.withReader(charset: String, block: (Reader) -> Unit) =
    bufferedReader(charset(charset)).use(block)

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

android {
    namespace = "com.ragonha.k9ops"
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
        applicationId = "com.ragonha.k9ops"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
        val localProperties = Properties()
        val localPropertiesFile = rootProject.file("local.properties")
        if (localPropertiesFile.exists()) {
            localPropertiesFile.withReader("UTF-8") { reader ->
                localProperties.load(reader)
            }
        }
        val mapsApiKey = (project.findProperty("MAPS_API_KEY") as? String)
            ?: System.getenv("MAPS_API_KEY")
            ?: localProperties.getProperty("MAPS_API_KEY")
            ?: ""
        manifestPlaceholders["MAPS_API_KEY"] = mapsApiKey
    }

    val keystorePropertiesFile = rootProject.file("key.properties")
    val keystoreProperties = Properties()
    if (keystorePropertiesFile.exists()) {
        keystorePropertiesFile.withReader("UTF-8") { reader ->
            keystoreProperties.load(reader)
        }
    }

    val storeFilePath = keystoreProperties.getProperty("storeFile")?.trim()
    val storeFileCandidate = if (!storeFilePath.isNullOrEmpty()) {
        val candidate = File(storeFilePath)
        if (candidate.isAbsolute) candidate else rootProject.file(storeFilePath)
    } else null

    val releaseKeyAlias = keystoreProperties.getProperty("keyAlias")?.trim()
    val releaseStorePassword = keystoreProperties.getProperty("storePassword")
    val releaseKeyPassword = keystoreProperties.getProperty("keyPassword")

    val hasCompleteReleaseConfig = keystorePropertiesFile.exists() &&
        storeFileCandidate != null &&
        storeFileCandidate.exists() &&
        !releaseKeyAlias.isNullOrEmpty() &&
        !releaseStorePassword.isNullOrEmpty() &&
        !releaseKeyPassword.isNullOrEmpty()

    signingConfigs {
        create("release") {
            if (hasCompleteReleaseConfig) {
                storeFile = storeFileCandidate
                keyAlias = releaseKeyAlias
                storePassword = releaseStorePassword
                keyPassword = releaseKeyPassword
            }
        }
    }

    gradle.taskGraph.whenReady {
        val isProductionReleaseRequested = allTasks.any { task ->
            val name = task.name
            name.contains("ProductionRelease", ignoreCase = true)
        }
        if (isProductionReleaseRequested && !hasCompleteReleaseConfig) {
            val missingReasons = mutableListOf<String>()
            if (!keystorePropertiesFile.exists()) {
                missingReasons.add("key.properties file is missing at ${keystorePropertiesFile.absolutePath}")
            }
            if (storeFilePath.isNullOrEmpty()) {
                missingReasons.add("property 'storeFile' is missing or blank")
            } else if (storeFileCandidate == null || !storeFileCandidate.exists()) {
                missingReasons.add("keystore file does not exist at ${storeFileCandidate?.absolutePath ?: storeFilePath}")
            }
            if (releaseKeyAlias.isNullOrEmpty()) {
                missingReasons.add("property 'keyAlias' is missing or blank")
            }
            if (releaseStorePassword.isNullOrEmpty()) {
                missingReasons.add("property 'storePassword' is missing or blank")
            }
            if (releaseKeyPassword.isNullOrEmpty()) {
                missingReasons.add("property 'keyPassword' is missing or blank")
            }
            throw GradleException(
                "FAIL-CLOSED: Production release signing requires a valid release configuration, but: " +
                missingReasons.joinToString("; ") +
                ". Silently falling back to debug signing is strictly forbidden."
            )
        }
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
            // Herda defaultConfig.applicationId = "com.ragonha.k9ops"
            signingConfig = signingConfigs.getByName("release")
        }
        create("staging") {
            dimension = "environment"
            applicationId = "com.example.canil_gcm.staging"
            versionNameSuffix = "-stg"
            signingConfig = signingConfigs.getByName("debug")
            // O rótulo visível vem do source-set `src/staging/res`, que
            // sobrepõe `src/main/res` — não de `resValue`, para não duplicar
            // recurso com o `strings.xml` de main.
        }
    }

    buildTypes {
        release {
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

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.libraryai.library_ai"
    compileSdk = flutter.compileSdkVersion

    // Pinned to the NDK that fllama's build hook is verified against. Letting
    // this float produces "plugin(s) depend on a different Android NDK version"
    // failures during the native assets build.
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.libraryai.library_ai"
        // API 26 keeps us clear of the older native-library packaging paths and
        // is well below the target device (Android 15 / API 35).
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Release keystore supplied via CI secrets or a local environment.
    // SIGNING_MODE = unsigned | signed | debug-keys (default)
    val keystorePath = System.getenv("KEYSTORE_PATH")
    val keystorePassword = System.getenv("KEYSTORE_PASSWORD")
    val keyAliasEnv = System.getenv("KEY_ALIAS")
    val keyPassword = System.getenv("KEY_PASSWORD")
    val hasReleaseKeystore =
        !keystorePath.isNullOrBlank() &&
            !keystorePassword.isNullOrBlank() &&
            !keyAliasEnv.isNullOrBlank() &&
            !keyPassword.isNullOrBlank() &&
            file(keystorePath).exists()

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                storeFile = file(keystorePath!!)
                storePassword = keystorePassword
                keyAlias = keyAliasEnv
                keyPassword = keyPassword
            }
        }
    }

    buildTypes {
        release {
            val mode = (System.getenv("SIGNING_MODE") ?: "debug-keys").lowercase()
            when {
                mode == "unsigned" -> {
                    signingConfig = null
                }
                mode == "signed" && hasReleaseKeystore -> {
                    signingConfig = signingConfigs.getByName("release")
                }
                else -> {
                    // Local `flutter run --release`, and CI without secrets.
                    signingConfig = signingConfigs.getByName("debug")
                }
            }
        }
    }

    // Ship only the ABI the target device uses. Cutting armeabi-v7a and x86
    // roughly halves APK size and avoids bundling a 32-bit llama.cpp that the
    // S25 will never load.
    packaging {
        jniLibs {
            useLegacyPackaging = false
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

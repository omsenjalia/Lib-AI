plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.libraryai.library_ai"

    // flutter_local_notifications requires compileSdk 37 at a minimum; the
    // maxOf keeps following Flutter once its default catches up.
    compileSdk = maxOf(flutter.compileSdkVersion, 37)

    // Pinned to the NDK that fllama's build hook is verified against. Letting
    // this float produces "plugin(s) depend on a different Android NDK version"
    // failures during the native assets build.
    ndkVersion = "28.2.13676358"

    compileOptions {
        // flutter_local_notifications schedules through java.time, so the
        // plugin requires core library desugaring on every app that includes
        // it - whether or not it schedules anything. See the dependencies
        // block at the end of this file for the library itself.
        isCoreLibraryDesugaringEnabled = true
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

        // The plugin's Gradle setup asks for this alongside desugaring. It is
        // a no-op at minSdk 26 (multidex is native from API 21) but keeps the
        // app matching the documented configuration.
        multiDexEnabled = true

        ndk {
            // Package arm64-v8a for the phone and x86_64 so the app can still be
            // run on a desktop emulator. The two 32-bit ABIs are dropped: nothing
            // here targets a 32-bit device, and a 32-bit llama.cpp is slow and
            // memory-limited anyway. `flutter build apk` still compiles every
            // ABI's native code; this decides which ones land in the APK.
            abiFilters += listOf("arm64-v8a", "x86_64")
        }
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

    packaging {
        jniLibs {
            // Store .so files uncompressed and page-aligned instead of the
            // legacy "compress and extract at install" behaviour. This is the
            // modern default for minSdk 26 and it keeps startup from waiting on
            // an unpack of a large native library.
            useLegacyPackaging = false
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // The desugared java.time backport flutter_local_notifications needs.
    // 2.1.4 is the version its README pins.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}

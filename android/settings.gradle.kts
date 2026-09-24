pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    // 9.1.1 is the floor flutter_local_notifications publishes its own Android
    // library against; a lower AGP fails while resolving that plugin's module.
    id("com.android.application") version "9.1.1" apply false
    // No `org.jetbrains.kotlin.android`: AGP 9 compiles Kotlin itself, and
    // applying the Kotlin Gradle plugin on top of it is rejected. The
    // `kotlin { compilerOptions { ... } }` block in app/build.gradle.kts still
    // sets the JVM target.
}

include(":app")

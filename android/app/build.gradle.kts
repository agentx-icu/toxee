import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")

if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

// Per-machine overrides from the gitignored local.properties (e.g. an
// `flutter.ndkVersion=<version>` override when the default Flutter NDK is not
// installed cleanly on this machine). Committed config stays portable.
val localProperties = Properties()
val localPropertiesFile = rootProject.file("local.properties")
if (localPropertiesFile.exists()) {
    localPropertiesFile.inputStream().use { localProperties.load(it) }
}

android {
    namespace = "com.toxee.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = localProperties.getProperty("flutter.ndkVersion") ?: flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        // flutter_local_notifications 19+ needs core-library desugaring for
        // its java.time / ZoneId usage at runtime on minSdk < 26.
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.toxee.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // androidx.camera:camera-video 1.5.0 requires minSdk >= 23, so we raise
        // the floor above Flutter's default (21). The manifest merger rejects
        // the build otherwise.
        minSdk = maxOf(23, flutter.minSdkVersion)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Package only the ABIs for which the tim2tox FFI .so was actually
        // built (build_android_ffi.sh stages per-ABI libs into jniLibs).
        // Otherwise Gradle packages Flutter's default ABIs even where
        // libtim2tox_ffi.so is absent, and DynamicLibrary.open() fails at
        // runtime on that ABI. (codex review 2026-06-16.)
        val ffiAbis = file("src/main/jniLibs").listFiles()
            ?.filter { it.isDirectory && it.resolve("libtim2tox_ffi.so").exists() }
            ?.map { it.name }?.sorted() ?: emptyList()
        if (ffiAbis.isNotEmpty()) {
            ndk { abiFilters.addAll(ffiAbis) }
        } else {
            // jniLibs is gitignored, so a clean checkout has no FFI yet. Fail
            // fast rather than ship a libtim2tox_ffi.so-less APK that crashes on
            // every ABI at runtime. Build it first: tool/build_android_ffi.sh.
            throw GradleException(
                "libtim2tox_ffi.so not found under android/app/src/main/jniLibs/ " +
                    "— run tool/build_android_ffi.sh before building the Android app."
            )
        }
    }

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            // Prefer a user-supplied release keystore when available, but keep
            // debug-key signing as the default so CI can still build artifacts.
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // androidx.core: NotificationCompat used by ToxPollingService for the
    // persistent foreground-service notification. Pulled in transitively by
    // flutter_local_notifications already, but declared explicitly so the
    // dependency isn't load-bearing on a plugin's version pin.
    implementation("androidx.core:core-ktx:1.13.1")
}

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

// Gradle packages whatever is staged in jniLibs, so this is the LAST place a
// test-only tim2tox hook can be caught before it lands in an APK — and the only
// one the scripts do not cover, because --ffi-lib-dir stages a prebuilt straight
// into that directory and `flutter build apk` never touches those scripts.
//
// Done in Kotlin rather than by shelling out to tool/ci/assert_no_test_hooks.sh
// on purpose: an Android build must work on a host with no bash. But the symbol
// NAMES are read out of that script, so there is still exactly one list to
// maintain — test/ci/test_hook_symbol_list_test.dart is what keeps it complete.
// Export names are plain ASCII in the ELF .dynstr, so a byte scan finds them; it
// errs towards failing, since it also matches a non-exported occurrence.
fun forbiddenTestHookNames(repoRoot: File): List<String> {
    val gate = File(repoRoot, "tool/ci/assert_no_test_hooks.sh")
    if (!gate.isFile) {
        throw GradleException(
            "tool/ci/assert_no_test_hooks.sh is missing — cannot verify that the " +
                "staged libtim2tox_ffi.so carries no test-only hook."
        )
    }
    val pattern = Regex("^FORBIDDEN_[A-Z_]*=\"([^\"\$]+)\"", RegexOption.MULTILINE)
    val names = pattern.findAll(gate.readText()).map { it.groupValues[1] }.toList()
    if (names.isEmpty()) {
        throw GradleException(
            "no FORBIDDEN_* names parsed from tool/ci/assert_no_test_hooks.sh — " +
                "the gate's format changed and this check would silently pass."
        )
    }
    return names
}

fun assertNoTestHooks(lib: File, forbidden: List<String>) {
    if (!lib.isFile) return
    val bytes = lib.readBytes()
    for (name in forbidden) {
        val needle = name.toByteArray(Charsets.US_ASCII)
        var i = 0
        outer@ while (i <= bytes.size - needle.size) {
            for (j in needle.indices) {
                if (bytes[i + j] != needle[j]) {
                    i++
                    continue@outer
                }
            }
            throw GradleException(
                "${lib.path} carries the TEST-ONLY tim2tox hook $name and must not " +
                    "be packaged. It was built with -DTIM2TOX_ENABLE_TEST_HOOKS=ON " +
                    "(build_ffi.sh defaults it on for the auto_tests). Rebuild with " +
                    "the option OFF — tool/build_android_ffi.sh passes it — or delete " +
                    "the staged artifact."
            )
        }
    }
}

fun isUnitTestOnlyInvocation(taskNames: List<String>): Boolean {
    if (taskNames.isEmpty()) return false
    return taskNames.all { taskName ->
        val lowerName = taskName.lowercase()
        lowerName == "test" || lowerName.endsWith(":test") || lowerName.contains("unittest")
    }
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
            // Checked here, where the bytes about to be packaged are. A unit-test
            // invocation packages nothing, so it is skipped for the same reason
            // the branch below skips its own failure.
            if (!isUnitTestOnlyInvocation(gradle.startParameter.taskNames)) {
                val forbidden = forbiddenTestHookNames(rootProject.file(".."))
                for (abi in ffiAbis) {
                    assertNoTestHooks(
                        file("src/main/jniLibs/" + abi + "/libtim2tox_ffi.so"),
                        forbidden,
                    )
                }
            }
        } else if (!isUnitTestOnlyInvocation(gradle.startParameter.taskNames)) {
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
    testImplementation("junit:junit:4.13.2")
}

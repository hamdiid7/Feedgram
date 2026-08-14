plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.omotic.feedgram"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.omotic.feedgram"
        // handy_tdlib requires minSdk 21; Flutter's floor is already higher.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Debug keystore is enough for personal sideloading; there is no
            // Play Store target.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

// Keep only the ABI actually being built for.
//
// `--target-platform` filters Flutter's own libs but NOT a plugin's prebuilt
// jniLibs, and handy_tdlib ships four ABIs of libtdjson/libssl/libcrypto at
// ~30 MB each. Without this the APK carries three sets it can never load.
// `defaultConfig.ndk.abiFilters` does not work for this: the Flutter Gradle
// plugin sets abiFilters per variant and wins.
//
// This follows `--target-platform` rather than hardcoding arm64 for release. A
// fixed exclusion list is a trap in both directions: these patterns match
// Flutter's own libflutter.so and libapp.so too, so stripping x86_64 from a
// build meant for an emulator leaves it with no engine at all, and stripping
// nothing from debug produced a 228 MB APK that would not fit on the emulator's
// /data partition.
val ALL_ABIS = listOf("armeabi-v7a", "arm64-v8a", "x86", "x86_64")

fun abiFor(platform: String): String? = when (platform) {
    "android-arm" -> "armeabi-v7a"
    "android-arm64" -> "arm64-v8a"
    "android-x86" -> "x86"
    "android-x64" -> "x86_64"
    else -> null
}

// Flutter passes `-Ptarget-platform=...` through to Gradle for every build.
val requestedAbis: Set<String> = (project.findProperty("target-platform") as String?)
    ?.split(",")
    ?.mapNotNull { abiFor(it.trim()) }
    ?.toSet()
    .orEmpty()

androidComponents {
    onVariants { variant ->
        // Fallbacks matter: if that property ever stops being passed, release
        // still ships arm64 for the phone and debug still ships everything,
        // which is exactly the behaviour this replaced. A wrong guess here is a
        // crash on launch, so absent information means strip nothing.
        val keep = when {
            requestedAbis.isNotEmpty() -> requestedAbis
            variant.buildType == "release" -> setOf("arm64-v8a")
            else -> ALL_ABIS.toSet()
        }
        variant.packaging.jniLibs.excludes.addAll(
            ALL_ABIS.filterNot { it in keep }.map { "lib/$it/**" },
        )
    }
}

flutter {
    source = "../.."
}

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

// Strip non-arm64 native libs from **release** only.
//
// `--target-platform android-arm64` filters Flutter's own libs but NOT a
// plugin's prebuilt jniLibs, and handy_tdlib ships four ABIs — without this the
// release APK carries ~30 MB of libtdjson/libssl/libcrypto it can never load
// (74 MB -> 37 MB). `defaultConfig.ndk.abiFilters` does not work for this: the
// Flutter Gradle plugin sets abiFilters per variant and wins.
//
// Debug keeps every ABI on purpose. The pattern matches Flutter's libflutter.so
// and libapp.so too, so excluding x86_64 globally leaves an x86_64 emulator with
// no engine at all, not just no TDLib.
androidComponents {
    onVariants(selector().withBuildType("release")) { variant ->
        variant.packaging.jniLibs.excludes.addAll(
            "lib/armeabi-v7a/**",
            "lib/x86/**",
            "lib/x86_64/**",
        )
    }
}

flutter {
    source = "../.."
}

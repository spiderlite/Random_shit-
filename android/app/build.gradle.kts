plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "dev.haul.haul"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "dev.haul.haul"
        // youtubedl-android ships Python for API 24+.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // The engine library also ships 32-bit x86, which Flutter doesn't.
        // Keep universal APKs to ABIs both support (`--split-per-abi`
        // filters on its own and rejects this setting).
        if (!project.hasProperty("split-per-abi")) {
            ndk {
                abiFilters += listOf("arm64-v8a", "armeabi-v7a", "x86_64")
            }
        }
    }

    packaging {
        // The bundled Python/ffmpeg are executed from the native lib dir,
        // so they must be extracted on install.
        jniLibs {
            useLegacyPackaging = true
            // These are zip archives named .so so Android installs them;
            // there is nothing to strip.
            keepDebugSymbols += listOf("**/libpython.zip.so", "**/libffmpeg.zip.so")
        }
    }

    buildTypes {
        release {
            // Signed with the debug key so CI builds install out of the box.
            // For store releases, add a real signing config here.
            signingConfig = signingConfigs.getByName("debug")
            // No R8 shrinking/renaming: youtubedl-android (and the
            // commons-compress code it uses to unpack Python on first run)
            // looks classes up by name. Renaming them broke engine start-up
            // in 0.1.0 ("r8"). The Java code is tiny next to the bundled
            // Python and ffmpeg, so this costs almost nothing.
            isMinifyEnabled = false
            isShrinkResources = false
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
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

dependencies {
    implementation("io.github.junkfood02.youtubedl-android:library:0.18.1")
    implementation("io.github.junkfood02.youtubedl-android:ffmpeg:0.18.1")
    implementation("androidx.core:core-ktx:1.17.0")
}

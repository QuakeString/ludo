plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.quakestring.ludo_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.quakestring.ludo_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // One fixed key for every published build, so a new APK installs over
    // the old one. Flutter's debug key is made fresh on each machine, and
    // every CI runner is a fresh machine: each build came out signed
    // differently, and Android will not update an app whose signature has
    // changed. CI writes the key from the repository's secrets; without them
    // (a local build, a pull request) the debug key is used as before.
    val keystore = System.getenv("LUDO_KEYSTORE")?.let { file(it) }
    val signed = keystore != null && keystore.exists()
    if (signed) {
        signingConfigs {
            create("upload") {
                storeFile = keystore
                storePassword = System.getenv("LUDO_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("LUDO_KEY_ALIAS") ?: "ludo"
                keyPassword = System.getenv("LUDO_KEYSTORE_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(if (signed) "upload" else "debug")
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

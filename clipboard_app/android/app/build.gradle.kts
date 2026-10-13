import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseProperties = Properties()
val signingPath = System.getenv("SHARED_CLIPBOARD_SIGNING_PROPERTIES")
if (!signingPath.isNullOrBlank()) {
    file(signingPath).inputStream().use { releaseProperties.load(it) }
}


android {
    namespace = "com.chatall.clipboard.clipboard_app"
    compileSdk = flutter.compileSdkVersion
    // Locked JNI dependencies require r28c; use the highest compatible NDK.
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.chatall.clipboard.clipboard_app"
        // Keep the supported Android baseline aligned with the pinned Flutter SDK.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (!signingPath.isNullOrBlank()) {
            create("sharedClipboardRelease") {
                storeFile = file(releaseProperties.getProperty("storeFile"))
                storePassword = releaseProperties.getProperty("storePassword")
                keyAlias = releaseProperties.getProperty("keyAlias")
                keyPassword = releaseProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (signingPath.isNullOrBlank()) null else signingConfigs.getByName("sharedClipboardRelease")
        }
    }
}

flutter {
    source = "../.."
}

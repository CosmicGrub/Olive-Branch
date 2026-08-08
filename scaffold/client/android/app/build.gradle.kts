plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.olivebranch.olive_client"
    // jitsi_meet_flutter_sdk's transitive androidx.media3/androidx.core deps
    // require compiling against API 35+; flutter.compileSdkVersion alone
    // resolved lower and failed the build with a real dependency-resolution
    // error, not a guess.
    compileSdk = maxOf(flutter.compileSdkVersion, 36)
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.olivebranch.olive_client"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // jitsi_meet_flutter_sdk's README says API 24+, but the actual AAR
        // (org.jitsi.react:jitsi-meet-sdk:13.1.0) declares minSdkVersion 26 in
        // its own manifest — confirmed by a real manifest-merger failure, not
        // assumed from the docs. Both target devices run Android 14+.
        minSdk = maxOf(flutter.minSdkVersion, 26)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
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
    // Wear Data Layer API — phone side. Lets WearSyncBridge.kt push
    // sleepsUntilHandover to a paired Galaxy Watch6 companion (§21.5) via
    // DataClient.putDataItem(). Version matches the wear module's own
    // play-services-wearable dependency (android/wear/build.gradle.kts) —
    // the two sides of one Data Layer conversation should not drift onto
    // different major versions of the API that carries it.
    implementation("com.google.android.gms:play-services-wearable:19.0.0")
    // §16.2 #6 — MainActivity.kt relays WrapperJitsiMeetActivity's mid-call
    // defeat broadcast (see KioskBridge.ACTION_CALL_LOCK_TASK_EXITED). The
    // jitsi_meet_flutter_sdk module already uses this class itself (it's a
    // transitive dependency of org.jitsi:jitsi-meet-sdk), but Flutter wires
    // plugin modules in as `implementation`, which does not expose their own
    // transitive deps to this module's compile classpath — confirmed by
    // `compileDebugKotlin` failing with "Unresolved reference
    // 'localbroadcastmanager'" without this explicit line.
    implementation("androidx.localbroadcastmanager:localbroadcastmanager:1.1.0")
}

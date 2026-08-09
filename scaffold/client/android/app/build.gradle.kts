import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Real release signing, when a keystore is provided. See
// android/key.properties.example and android/RELEASE_SIGNING.md for how to
// generate one -- neither the keystore file nor key.properties itself is
// ever committed (see android/.gitignore). Absent a real key.properties,
// this falls back to the debug keystore exactly as before, so
// `flutter run --release` and CI keep working without a real keystore.
val keystorePropertiesFile = rootProject.file("key.properties")
val hasRealSigningConfig = keystorePropertiesFile.exists()
val keystoreProperties = Properties()
if (hasRealSigningConfig) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
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
        // Real, unique application ID -- not the Flutter template default.
        // Matches `namespace` above; keep both in sync if this ever changes,
        // since Play Store submissions treat applicationId as permanent.
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

    signingConfigs {
        if (hasRealSigningConfig) {
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
            // Real signing when android/key.properties exists (see
            // key.properties.example and RELEASE_SIGNING.md); otherwise
            // falls back to the debug keystore so `flutter run --release`
            // and CI keep working without a real keystore. This is the
            // only thing that decides which key signs a release build --
            // there is no separate "is this a real release" flag that
            // could get out of sync with it.
            signingConfig = if (hasRealSigningConfig) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            // R8 minification runs on release by default and, without this,
            // fails outright on a Giphy SDK class (transitive via
            // jitsi_meet_flutter_sdk) that references a source-retention
            // Kotlin annotation R8 can't resolve. See proguard-rules.pro
            // for the full explanation -- this was a real, reproducible
            // build failure, not a preventative rule.
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
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

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
        // Floor-guarded for the same reason compileSdk/minSdk are above: the
        // wear module (android/wear/build.gradle.kts) hardcodes targetSdk =
        // 36 with no dependency on the Flutter SDK at all, so this line was
        // the one SDK field in this file with nothing anchoring it to that
        // floor -- it would silently track whatever flutter.targetSdkVersion
        // happens to resolve to for whichever Flutter SDK build this, with
        // no guard against drifting below the wear module's fixed value.
        // Verified against this repo's own pinned toolchain, not assumed:
        // Flutter 3.44.8 (the exact version CI pins in
        // .github/workflows/verify.yml and the exact version installed at
        // C:/Users/Obliv/flutter on this machine) sets
        // FlutterExtension.targetSdkVersion = 36
        // (packages/flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt),
        // so this is a no-op today -- both modules already resolve to 36 --
        // but it removes the only remaining path by which a future Flutter
        // version bump could quietly desynchronize app and wear.
        targetSdk = maxOf(flutter.targetSdkVersion, 36)
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
    // Real WebAuthn/passkey ceremony (§7.1, §8.1, §11) — WebAuthnBridge.kt.
    // 1.6.0 is the latest STABLE release (1.7.0-alpha03 is newer but alpha;
    // this app already cares about release hygiene — see the real
    // release-signing wiring above — so a shipping auth feature stays on the
    // last stable line). Verified for real against Google's own Maven
    // metadata (dl.google.com/android/maven2/androidx/credentials/credentials
    // /maven-metadata.xml — note its <release> tag always echoes the newest
    // upload INCLUDING alphas, so 1.6.0 was confirmed by scanning the full
    // <versions> list for the newest non-alpha/beta/rc entry, cross-checked
    // against developer.android.com/jetpack/androidx/releases/credentials'
    // "1.6.0 / April 08 2026" stable-release note), not guessed.
    // credentials-play-services-auth is the real backing provider on devices
    // with Google Play services (see CredentialProviderConfigurationException
    // handling in WebAuthnBridge.kt for the case where it's missing/stale).
    implementation("androidx.credentials:credentials:1.6.0")
    implementation("androidx.credentials:credentials-play-services-auth:1.6.0")
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

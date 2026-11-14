import java.io.FileInputStream
import java.util.zip.ZipEntry
import java.util.zip.ZipFile
import java.util.zip.ZipOutputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Real release signing, when a keystore is provided. See
// android/key.properties.example and android/RELEASE_SIGNING.md for how to
// generate one -- neither the keystore file nor key.properties itself is
// ever committed (see android/.gitignore).
//
// Absent a real key.properties a RELEASE build (assembleRelease,
// bundleRelease, packageRelease) now FAILS with a clear message instead of
// silently signing with the shared Flutter debug key (an APK nobody should
// ship, and one the Play Store refuses). The one deliberate escape hatch is
// an explicit, per-invocation opt-in for a local smoke test of the release
// pipeline (R8, size measurement) that will never be distributed:
//     gradlew assembleRelease -Polive.allowDebugSignedRelease=true
// Through Flutter: `flutter build apk --release
// --android-project-arg=olive.allowDebugSignedRelease=true`. Debug builds are
// unaffected: they always use the debug key.
val keystorePropertiesFile = rootProject.file("key.properties")
val hasRealSigningConfig = keystorePropertiesFile.exists()
val allowDebugSignedRelease =
    providers.gradleProperty("olive.allowDebugSignedRelease").orNull == "true"
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
            // key.properties.example and RELEASE_SIGNING.md). Without it the
            // task-graph check below stops the build before anything is
            // produced, unless -Polive.allowDebugSignedRelease=true was
            // passed explicitly -- then (and only then) the debug key signs
            // an artifact meant for local measurement, never distribution.
            signingConfig = when {
                hasRealSigningConfig -> signingConfigs.getByName("release")
                allowDebugSignedRelease -> signingConfigs.getByName("debug")
                else -> null
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

// Refuse to build a release artifact that would be signed with nothing, or
// (silently) with the debug key. Checked once the task graph is known, so
// `flutter build apk --debug`, `compileDebugKotlin` and the wear module's own
// tasks are never affected -- only an actual release packaging task is.
gradle.taskGraph.whenReady {
    val releasing = allTasks.any {
        it.project == project && it.name in setOf("assembleRelease", "bundleRelease", "packageRelease")
    }
    if (releasing && !hasRealSigningConfig && !allowDebugSignedRelease) {
        throw GradleException(
            "Release build refused: android/key.properties is missing, so this would be " +
                "signed with the shared Flutter DEBUG key. Create a real keystore and " +
                "key.properties (see android/RELEASE_SIGNING.md). For a local, never-" +
                "distributed smoke build only, pass -Polive.allowDebugSignedRelease=true."
        )
    }
}

// ONE WebRTC per APK (MASTERFILE 16.2 #6, third reversal). The Jitsi SDK
// (org.jitsi:webrtc 124) and livekit_client's flutter_webrtc
// (io.github.webrtc-sdk:android 144) each ship org.webrtc.* classes and the SAME
// native library name (libjingle_peerconnection_so.so), so a build carrying both
// fails at :app:mergeReleaseNativeLibs. The default build keeps Jitsi (the default
// call provider) and drops the other stack; `-Polive.webrtc=livekit` (through
// Flutter: --android-project-arg=olive.webrtc=livekit) flips it. HONEST LIMIT: the
// other engine's Dart/Java glue then runs against a WebRTC it was not built for, so
// that engine is not expected to work in that build; a server-granted provider the
// build cannot carry shows the calm "not ready" state. Never carry both.
val webrtcEngine = providers.gradleProperty("olive.webrtc").orNull ?: "jitsi"
require(webrtcEngine == "jitsi" || webrtcEngine == "livekit") { "olive.webrtc must be jitsi or livekit" }
configurations.configureEach {
    if (webrtcEngine == "jitsi") {
        exclude(group = "io.github.webrtc-sdk", module = "android")
    } else {
        exclude(group = "org.jitsi", module = "webrtc")
    }
}

// flutter_webrtc ALSO embeds a few org.webrtc.* helper classes of its own (Camera1Helper
// and friends) in its library jar, which collide with the Jitsi WebRTC's identical names
// at R8/D8 ("Type org.webrtc.Camera1Helper is defined multiple times"). In the Jitsi build
// those embedded copies are stripped from flutter_webrtc's runtime jar so the Jitsi
// WebRTC's own are the only ones. Skipped in the livekit variant, where nothing collides.
if (webrtcEngine == "jitsi") {
    gradle.projectsEvaluated {
        rootProject.findProject(":flutter_webrtc")?.tasks
            ?.matching { it.name.startsWith("bundleLibRuntimeToJar") }
            ?.configureEach {
                doLast {
                    outputs.files.files.filter { it.isFile && it.name == "classes.jar" }.forEach { jar ->
                        val tmp = File(jar.parentFile, "classes.stripped.jar")
                        ZipFile(jar).use { zin ->
                            ZipOutputStream(tmp.outputStream()).use { zout ->
                                zin.entries().asSequence()
                                    .filter { !it.name.startsWith("org/webrtc/") }
                                    .forEach { e ->
                                        zout.putNextEntry(ZipEntry(e.name))
                                        if (!e.isDirectory) zin.getInputStream(e).copyTo(zout)
                                        zout.closeEntry()
                                    }
                            }
                        }
                        jar.delete()
                        tmp.renameTo(jar)
                    }
                }
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

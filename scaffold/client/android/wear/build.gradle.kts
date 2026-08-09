// OLIVE BRANCH — Galaxy Watch6 Classic / Wear OS companion. MASTERFILE §21.5.
//
// A SEPARATE native module, not Flutter shrunk onto a watch face. Flutter has
// no first-class Wear OS target (unlike Android/iOS/Windows/macOS/Linux/web),
// and even where community embedding exists, a full Flutter engine is a poor
// fit for a device this glance-oriented and battery-constrained. Wear Compose
// -- Google's own toolkit for exactly this class of screen -- is the
// idiomatic choice, matching the standard "Flutter phone app + native Wear OS
// companion, synced via the Data Layer API" pattern.
//
// Scope for this pass: compiles and installs as a real, standalone-launchable
// app. Phone<->watch sync via the Wear Data Layer API is NOT implemented yet
// -- MainActivity.kt's own header says so plainly. §21.5's "the quieting"
// principle (the product should feel LESS present as it matures, never more)
// argues directly against a watch face that mirrors the whole phone app: this
// is deliberately a small, glanceable surface, not a second ChildHome.
// AGP 9's built-in Kotlin support covers this module already (see :app's own
// build file, which applies neither org.jetbrains.kotlin.android nor a
// kotlinOptions{} block for exactly this reason) -- the compose-compiler
// plugin is still needed explicitly since built-in Kotlin doesn't imply it.
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.plugin.compose") version "2.3.20"
}

android {
    namespace = "com.olivebranch.olive_client.wear"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.olivebranch.olive_client.wear"
        // Wear OS 4+ (Galaxy Watch6 Classic ships Wear OS 5 / One UI Watch 6).
        minSdk = 30
        targetSdk = 36
        versionCode = 1
        versionName = "0.1.0"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        compose = true
    }
}

// Modern compilerOptions DSL -- the old android{ kotlinOptions{} } block is a
// hard error under this project's AGP 9 / newDsl=true configuration, not
// merely deprecated (confirmed by a real build failure, not assumed).
kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    implementation("androidx.wear.compose:compose-material:1.4.1")
    implementation("androidx.wear.compose:compose-foundation:1.4.1")
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("com.google.android.gms:play-services-wearable:19.0.0")
    implementation("androidx.wear:wear:1.3.0")
}

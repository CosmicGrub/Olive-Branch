allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// jitsi_meet_flutter_sdk (v13.1.0)'s own android/build.gradle hardcodes
// compileSdk 34, but its bundled androidx.media3/androidx.core versions
// require 35+ — confirmed by a real manifest/dependency-resolution failure.
// AGP reads and locks compileSdk during that subproject's OWN script
// evaluation (confirmed by trying: subprojects{afterEvaluate{}} here throws
// "already evaluated"; subprojects{withPlugin{...}} here gets silently
// clobbered by the subproject's own later `compileSdk 34` line; even
// withPlugin{afterEvaluate{}} throws "too late to set compileSdk — it has
// already been read"). There is no supported way to override another
// module's compileSdk from the including project for this AGP version — see
// the one-line patch this required in jitsi_meet_flutter_sdk-13.1.0's own
// android/build.gradle (noted in MASTERFILE.md's Jitsi decision entry).

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

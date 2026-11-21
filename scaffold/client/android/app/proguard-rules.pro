# jitsi_meet_flutter_sdk pulls in the Giphy Android SDK (com.giphy.sdk.*)
# transitively for its in-call GIF picker. Giphy's own analytics classes
# (e.g. com.giphy.sdk.analytics.models.AnalyticsEvent) are annotated with
# @kotlinx.parcelize.Parcelize, but that annotation is source-retention --
# it exists only to drive the Kotlin compiler's Parcelize plugin at build
# time and is never present in compiled bytecode or needed at runtime.
# Neither this app nor any of its other dependencies applies the
# kotlin-parcelize Gradle plugin (nothing here uses @Parcelize directly),
# so R8 has no way to resolve the reference and, in this AGP/R8 version,
# treats "missing class" as a hard error rather than a warning by default.
#
# This is exactly the rule Android's own tooling generates and recommends
# for this situation (see build/app/outputs/mapping/release/missing_rules.txt
# after a failed release build) -- confirmed against a real R8 failure,
# not applied speculatively.
-dontwarn kotlinx.parcelize.Parcelize

# One WebRTC per APK (see build.gradle.kts, olive.webrtc). In the default Jitsi
# build flutter_webrtc's Java glue (com.cloudwebrtc.*, used only by the selectable
# LiveKit engine) references org.webrtc classes that Jitsi's older WebRTC does not
# have (AudioTrackSink, DataPacketCryptor...). Those paths are never reached unless a
# LiveKit grant is joined in a Jitsi-variant build, which is not supported (the call
# screen shows its calm "not ready" state). R8 must not treat that as a build error.
-dontwarn org.webrtc.**
-dontwarn com.cloudwebrtc.webrtc.**

# Jitsi Meet SDK is a React Native app underneath. R8 must not strip or rename what
# React Native and the SDK reach by reflection at startup (native modules, the Hermes
# runtime, JNI entry points). These are the keep rules the Jitsi sample app itself ships.
-keep class org.jitsi.meet.sdk.** { *; }
-keep class com.facebook.react.** { *; }
-keep class com.facebook.hermes.** { *; }
-keep class com.facebook.jni.** { *; }
-keep class com.swmansion.** { *; }
-dontwarn com.facebook.react.**
-dontwarn org.jitsi.meet.sdk.**

# The child message player (video_player_android) references RtspMediaSource; its standalone module is excluded
# in build.gradle.kts (Jitsi already bundles those classes), and rtsp:// is never played. Not a build error.
-dontwarn androidx.media3.exoplayer.rtsp.**

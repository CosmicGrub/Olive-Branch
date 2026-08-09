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

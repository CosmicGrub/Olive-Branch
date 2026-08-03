// OLIVE BRANCH — Windows kiosk bridge. MASTERFILE §5.20, §8.3.
//
// UNVERIFIED: no .NET toolchain exists in this repository. Not compiled, never
// run. Method and event names are contract-checked against the Dart side.
//
// Assigned Access is exitable with Ctrl+Alt+Del, so as on Android the job is to
// report the exit rather than to prevent it.
namespace Olive.Kiosk
{
    public static class AssignedAccessBridge
    {
        public const string MethodChannel = "app.olive/kiosk";
        public const string EventChannel  = "app.olive/kiosk_events";

        public const string MStart   = "startLockTask";
        public const string MStop    = "stopLockTask";
        public const string MMode    = "lockTaskMode";
        public const string MIsOwner = "isDeviceOwner";

        public const string EExited     = "lockTaskExited";
        public const string EBackground = "backgrounded";
        public const string EResumed    = "resumed";

        // Windows has no equivalent of device-owner lock, so the mode is always
        // reported as escapable. Never claim "locked" here.
        public static string CurrentMode() => "assigned";

        public static bool IsFullyLocked() => false;
    }
}

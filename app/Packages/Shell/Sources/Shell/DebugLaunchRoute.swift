#if DEBUG
public struct DebugLaunchRoute: Sendable, Hashable {
    public var bypassesFirstRun: Bool
    public var usesDebugSeed: Bool
    public var showsHealthKitProbe: Bool
    public var runsWatchPushProbe: Bool
    public var runsWorkoutKitPushProbe: Bool

    public static let none = DebugLaunchRoute(
        bypassesFirstRun: false,
        usesDebugSeed: false,
        showsHealthKitProbe: false,
        runsWatchPushProbe: false,
        runsWorkoutKitPushProbe: false
    )

    public static func classify(args: [String]) -> DebugLaunchRoute {
        let values = Set(args)
        let showsHealthKitProbe = values.contains("--healthkit-sim-spike")
        let runsWatchPushProbe = values.contains("--debug-watch-push")
        let runsWorkoutKitPushProbe = values.contains("--debug-workoutkit-push-probe")
        let usesDebugSeed = values.contains("--start-active")
            || values.contains("--jump-rest")
            || values.contains("--jump-transition")
            || values.contains("--jump-complete")
            || values.contains("--debug-today-plan")
        let bypassesFirstRun = showsHealthKitProbe
            || runsWatchPushProbe
            || runsWorkoutKitPushProbe
            || usesDebugSeed

        return DebugLaunchRoute(
            bypassesFirstRun: bypassesFirstRun,
            usesDebugSeed: usesDebugSeed,
            showsHealthKitProbe: showsHealthKitProbe,
            runsWatchPushProbe: runsWatchPushProbe,
            runsWorkoutKitPushProbe: runsWorkoutKitPushProbe
        )
    }
}
#endif

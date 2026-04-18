// BuildInfo.swift
//
// Surface the "BUILD x.y.z · COMMIT abcd" footer line at the bottom of the
// Settings screen. `CFBundleShortVersionString` + `CFBundleVersion` come
// from `Bundle.main.infoDictionary`; the commit hash is a compile-time
// constant set to `"dev"` for now and swapped for a real short SHA by a
// future release script.
//
// Tests can inject their own `BuildInfo` value directly — `SettingsViewModel`
// takes one as an init parameter rather than calling `Bundle.main`.

import Foundation

/// Static display strings for the build footer.
public struct BuildInfo: Equatable, Sendable {
    public let version: String
    public let build: String
    public let commit: String

    public init(version: String, build: String, commit: String) {
        self.version = version
        self.build = build
        self.commit = commit
    }

    /// Reads `CFBundleShortVersionString` + `CFBundleVersion` off the main
    /// bundle and pins the commit to `"dev"`. A future release script
    /// replaces the commit constant with the short SHA at build time.
    public static func fromMainBundle(commit: String = "dev") -> BuildInfo {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = (info["CFBundleShortVersionString"] as? String) ?? "0.0.0"
        let build = (info["CFBundleVersion"] as? String) ?? "0"
        return BuildInfo(version: version, build: build, commit: commit)
    }

    /// "build 0.0.1 (1) · commit dev" — rendered directly by the view.
    /// Kept lowercase per the app's copywriting rules even though the
    /// design reference uses ALL CAPS for this footer. The section
    /// titles (ALL CAPS monospace) carry the uppercase treatment; the
    /// footer is regular text.
    public var displayLine: String {
        "build \(version) (\(build)) · commit \(commit)"
    }
}

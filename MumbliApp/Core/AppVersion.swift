import Foundation

/// The version and commit the running app was built from.
///
/// Everything here is stamped into Info.plist by scripts/version-stamp.sh at
/// build time. The Mumbli* keys are absent in a build that skipped the stamp
/// phase (an old build, or a bare `xcodebuild` against a hand-edited project),
/// so every one of them has a fallback.
enum AppVersion {
    /// Release version, e.g. "0.4.0". Never carries build metadata.
    static let release: String = info("CFBundleShortVersionString") ?? "0.0.0"

    /// Short commit hash, or nil when the build had no git repository.
    static let commit: String? = {
        guard let value = info("MumbliGitCommit"), value != "unknown" else { return nil }
        return value
    }()

    /// `git describe` output, e.g. "v0.4.0-7-g363bc3d".
    static let describe: String? = info("MumbliGitDescribe")

    /// Commits landed since the tag matching `release`. 0 on a released build.
    static let commitsSinceTag: Int = Int(info("MumbliCommitsSinceTag") ?? "") ?? 0

    /// True when the working tree had uncommitted changes at build time.
    static let isDirty: Bool = info("MumbliSourceState") == "dirty"

    /// True for a build that sits exactly on a release tag with a clean tree.
    static var isRelease: Bool { commitsSinceTag == 0 && !isDirty }

    /// One line for bug reports: "0.4.0+7.g363bc3d.dirty" or just "0.4.0".
    static let full: String = {
        if let stamped = info("MumbliVersionDisplay") { return stamped }
        guard let commit else { return release }
        return "\(release)+\(commitsSinceTag).g\(commit)"
    }()

    /// The commit half on its own, for a UI that shows the version separately.
    /// nil when there is nothing to add beyond the release version.
    static var buildDetail: String? {
        guard let commit else { return nil }
        var detail = commit
        if commitsSinceTag > 0 { detail += " · +\(commitsSinceTag)" }
        if isDirty { detail += " · dirty" }
        return detail
    }

    private static func info(_ key: String) -> String? {
        (Bundle.main.infoDictionary?[key] as? String)?.trimmingCharacters(in: .whitespaces)
            .nilIfEmpty
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

//
//  PythonRunner.swift
//  Albert Script Runner
//
//  Runs the python-engine CLI (engine.py) using the venv interpreter.
//

import Foundation
import Dispatch

/// Responsible for executing the python-engine CLI and returning results.
struct PythonRunner {
    /// Resolves the python-engine directory.
    ///
    /// Priority order:
    ///  1) Bundled inside the app at: <App>.app/Contents/Resources/python-engine
    ///  2) Explicit override via environment variable: PYTHON_ENGINE_DIR
    ///  3) Development fallback: resolve relative to this Swift source file (repo checkout)
    ///
    /// This lets Debug runs in Xcode work without a Run Script phase that copies resources,
    /// while still supporting a fully bundled standalone app for distribution.
    nonisolated private static func bundledPythonEngineDirectory() throws -> URL {
        // 1) Bundled in the app
        if let resourcesURL = Bundle.main.resourceURL {
            let bundled = resourcesURL.appendingPathComponent("python-engine", isDirectory: true)
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: bundled.path, isDirectory: &isDir), isDir.boolValue {
                return bundled
            }
        }

        // 2) Explicit override (works for both Debug + custom installs)
        let env = ProcessInfo.processInfo.environment
        if let override = env["PYTHON_ENGINE_DIR"], !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let overridden = URL(fileURLWithPath: override)
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: overridden.path, isDirectory: &isDir), isDir.boolValue {
                return overridden
            } else {
                throw PythonRunnerError.runtimeError(
                    "PYTHON_ENGINE_DIR was set but did not point to a folder:\n" +
                    "  \(overridden.path)\n\n" +
                    "Fix: set PYTHON_ENGINE_DIR to the full path of your python-engine folder."
                )
            }
        }

        // 3) Development fallback: locate python-engine from the repo, without relying on the app bundle.
        // We derive an absolute path from this source file's location at build time.
        // Typical layout:
        //   <repo>/Albert Script Runner/PythonRunner.swift (or <repo>/<project>/Services/PythonRunner.swift)
        // and python-engine sits at:
        //   <repo>/python-engine
        // or:
        //   <repo>/<project>/python-engine
        let sourceFileURL = URL(fileURLWithPath: #filePath)
        let sourceDir = sourceFileURL.deletingLastPathComponent()

        // Walk up a few levels and try common locations.
        let candidateBases: [URL] = [
            sourceDir,
            sourceDir.deletingLastPathComponent(),
            sourceDir.deletingLastPathComponent().deletingLastPathComponent(),
            sourceDir.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent(),
            sourceDir.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        ]

        var tried: [String] = []
        for base in candidateBases {
            let direct = base.appendingPathComponent("python-engine", isDirectory: true)
            tried.append(direct.path)
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: direct.path, isDirectory: &isDir), isDir.boolValue {
                return direct
            }

            // If the repo has the Xcode project in a subfolder, also try one more nesting level.
            // e.g. <repo>/Albert Script Runner/python-engine
            // (Only do this if base looks like a project root by containing an .xcodeproj)
            if let entries = try? FileManager.default.contentsOfDirectory(atPath: base.path),
               entries.contains(where: { $0.hasSuffix(".xcodeproj") }) {
                let nested = base.appendingPathComponent("Albert Script Runner", isDirectory: true)
                    .appendingPathComponent("python-engine", isDirectory: true)
                tried.append(nested.path)
                if FileManager.default.fileExists(atPath: nested.path, isDirectory: &isDir), isDir.boolValue {
                    return nested
                }
            }
        }

        let bundledPath = (Bundle.main.resourceURL?.appendingPathComponent("python-engine", isDirectory: true).path)
            ?? "<Bundle.main.resourceURL was nil>"

        throw PythonRunnerError.runtimeError(
            "python-engine folder not found.\n\n" +
            "Tried bundled location:\n  \(bundledPath)\n\n" +
            "Also tried development locations (derived from #filePath):\n  \(tried.joined(separator: "\n  "))\n\n" +
            "Fix options:\n" +
            "  1) Debug in Xcode: set an env var in Scheme -> Run -> Arguments: PYTHON_ENGINE_DIR=<absolute path to python-engine>\n" +
            "  2) Distribution: add a Run Script build phase to copy python-engine into Contents/Resources/python-engine"
        )
    }

    /// Resolves engine.py inside the bundled python-engine folder.
    nonisolated private static func bundledEnginePyURL() throws -> URL {
        let engineDir = try bundledPythonEngineDirectory()
        let enginePy = engineDir.appendingPathComponent("engine.py")
        if !FileManager.default.fileExists(atPath: enginePy.path) {
            throw PythonRunnerError.runtimeError(
                "Bundled engine.py not found at: \(enginePy.path)\n" +
                "Expected: Contents/Resources/python-engine/engine.py"
            )
        }
        return enginePy
    }

    /// Attempts to resolve a bundled Python runtime.
    /// Returns the interpreter URL plus an optional PYTHONHOME root.
    /// Preferred location:
    ///   Contents/Frameworks/pythonAlbert.framework/Resources/python-runtime/bin/python3
    /// Alternate locations:
    ///   Contents/Resources/python-runtime/bin/python3
    ///   Contents/Resources/python-engine/python-runtime/bin/python3
    /// Fallback (NOT standalone):
    ///   Contents/Resources/python-engine/.venv/bin/python
    nonisolated private static func bundledPythonInterpreter() throws -> (url: URL, pythonHome: URL?) {
        let candidates = ["python3", "python3.12", "python3.13", "python"]

        // NOTE: We may run in two modes:
        //  - Bundled app (resourcesURL available and python-runtime possibly bundled)
        //  - Debug/dev mode (python-engine on disk next to the repo)
        //
        // 1) Preferred: runtime inside the embedded pythonAlbert.framework.
        if let frameworksURL = Bundle.main.privateFrameworksURL {
            let frameworkRuntimeRoot = frameworksURL
                .appendingPathComponent("pythonAlbert.framework", isDirectory: true)
                .appendingPathComponent("Resources", isDirectory: true)
                .appendingPathComponent("python-runtime", isDirectory: true)
            let frameworkBin = frameworkRuntimeRoot.appendingPathComponent("bin", isDirectory: true)
            for name in candidates {
                let cand = frameworkBin.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: cand.path) {
                    return (cand, frameworkRuntimeRoot)
                }
            }
        }

        // 2) Alternate: runtime at Contents/Resources/python-runtime/bin/
        if let resourcesURL = Bundle.main.resourceURL {
            let runtimeRoot = resourcesURL.appendingPathComponent("python-runtime", isDirectory: true)
            let runtimeBin = runtimeRoot.appendingPathComponent("bin", isDirectory: true)
            for name in candidates {
                let cand = runtimeBin.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: cand.path) {
                    return (cand, runtimeRoot)
                }
            }
        }

        let engineDir = try bundledPythonEngineDirectory()

        // 3) Alternate: runtime bundled inside python-engine
        let engineRuntimeRoot = engineDir.appendingPathComponent("python-runtime", isDirectory: true)
        let engineRuntimeBin = engineRuntimeRoot.appendingPathComponent("bin", isDirectory: true)
        for name in candidates {
            let cand = engineRuntimeBin.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: cand.path) {
                return (cand, engineRuntimeRoot)
            }
        }

        // 4) Fallback: venv interpreter inside python-engine
        let venvPython = engineDir.appendingPathComponent(".venv/bin/python")
        if FileManager.default.fileExists(atPath: venvPython.path) {
            // If it's a symlink to a system path, this will work only on the dev machine.
            // Detect that and provide a clearer error.
            do {
                let dest = try FileManager.default.destinationOfSymbolicLink(atPath: venvPython.path)
                if dest.hasPrefix("/") {
                    throw PythonRunnerError.runtimeError(
                        "Bundled venv python is a symlink to a system Python:\n" +
                        "  \(venvPython.path) -> \(dest)\n\n" +
                        "This will work on your machine but fail on coworkers' machines unless they have the same system Python installed.\n" +
                        "To make the app truly standalone, bundle a Python runtime at:\n" +
                        "  Contents/Frameworks/pythonAlbert.framework/Resources/python-runtime/bin/python3\n" +
                        "or at:\n" +
                        "  Contents/Resources/python-runtime/bin/python3\n" +
                        "or inside python-engine (legacy path) at:\n" +
                        "  Contents/Resources/python-engine/python-runtime/bin/python3\n" +
                        "and re-export the app/DMG."
                    )
                }
            } catch let err as PythonRunnerError {
                // This is our intentional, user-facing error — do not swallow it.
                throw err
            } catch {
                // If we can't readlink, just proceed.
            }
            return (venvPython, nil)
        }

        throw PythonRunnerError.runtimeError(
            "No bundled Python interpreter found.\n\n" +
            "Expected one of:\n" +
            "  - Contents/Frameworks/pythonAlbert.framework/Resources/python-runtime/bin/python3 (preferred)\n" +
            "  - Contents/Resources/python-runtime/bin/python3\n" +
            "  - Contents/Resources/python-engine/python-runtime/bin/python3\n" +
            "  - Contents/Resources/python-engine/.venv/bin/python (fallback)"
        )
    }

    /// Best-effort PYTHONPATH resolver for bundled site-packages.
    /// Preferred source: PYTHONHOME/lib/python3.X/site-packages
    /// Fallback source: python-engine/.venv/lib/python3.X/site-packages
    nonisolated private static func bundledSitePackagesPath(pythonHome: URL?) throws -> String? {
        if let pythonHome {
            let libDir = pythonHome.appendingPathComponent("lib", isDirectory: true)
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: libDir.path, isDirectory: &isDir), isDir.boolValue {
                let entries = (try? FileManager.default.contentsOfDirectory(atPath: libDir.path)) ?? []
                let pyDirName = entries.first(where: { $0.hasPrefix("python3") })
                if let pyDirName {
                    let site = libDir
                        .appendingPathComponent(pyDirName, isDirectory: true)
                        .appendingPathComponent("site-packages", isDirectory: true)
                    if FileManager.default.fileExists(atPath: site.path, isDirectory: &isDir), isDir.boolValue {
                        return site.path
                    }
                }
            }
        }

        let engineDir = try bundledPythonEngineDirectory()
        let libDir = engineDir.appendingPathComponent(".venv/lib", isDirectory: true)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: libDir.path, isDirectory: &isDir), isDir.boolValue else {
            return nil
        }

        // Look for .venv/lib/python3.X/site-packages
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: libDir.path)) ?? []
        let pyDirName = entries.first(where: { $0.hasPrefix("python3") })
        guard let pyDirName else { return nil }

        let site = libDir
            .appendingPathComponent(pyDirName, isDirectory: true)
            .appendingPathComponent("site-packages", isDirectory: true)

        if FileManager.default.fileExists(atPath: site.path, isDirectory: &isDir), isDir.boolValue {
            return site.path
        }
        return nil
    }

    /// Resolves a per-user writable path for Python bytecode cache output.
    /// This avoids writes inside the signed .app/.framework bundle.
    nonisolated private static func pythonBytecodeCachePrefixDirectory() throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let bundleName = (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let bundleID = Bundle.main.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)

        let appFolderName: String
        if let bundleName, !bundleName.isEmpty {
            appFolderName = bundleName
        } else if let bundleID, !bundleID.isEmpty {
            appFolderName = bundleID
        } else {
            appFolderName = "Albert Script Runner"
        }

        let safeFolderName = appFolderName.replacingOccurrences(of: "/", with: "-")
        let pycacheDir = appSupport
            .appendingPathComponent(safeFolderName, isDirectory: true)
            .appendingPathComponent("pycache", isDirectory: true)

        try FileManager.default.createDirectory(at: pycacheDir, withIntermediateDirectories: true)
        return pycacheDir
    }

    /// Default timeout for python-engine commands.
    nonisolated static let defaultTimeoutSeconds: TimeInterval = 120

    /// Redacts sensitive CLI args (for user-facing errors).
    nonisolated private static func redactedArgsString(_ args: [String]) -> String {
        var redacted: [String] = []
        var i = 0

        while i < args.count {
            let part = args[i]
            if part == "--token" {
                redacted.append(part)
                if i + 1 < args.count {
                    redacted.append("<redacted>")
                    i += 2
                    continue
                }
            }
            redacted.append(part)
            i += 1
        }

        return redacted.joined(separator: " ")
    }

    /// Runs the python engine with the given arguments.
    /// - Parameter args: Arguments AFTER engine.py (e.g. ["download-users", "--token", ...])
    /// - Returns: stdout as String
    /// - Throws: Error if python exits with non-zero status
    ///
    /// NOTE: Marked `nonisolated` to prevent Swift 6 actor-isolation issues if the type
    /// ever becomes annotated (directly or via extension) with @MainActor.
    nonisolated static func run(
        args: [String],
        timeoutSeconds: TimeInterval = defaultTimeoutSeconds
    ) throws -> String {
        let process = Process()
        let effectiveTimeout = max(1, timeoutSeconds)

        let python = try bundledPythonInterpreter()
        let pythonURL = python.url
        let engineURL = try bundledEnginePyURL()
        let engineDir = engineURL.deletingLastPathComponent()

        process.executableURL = pythonURL
        process.arguments = [engineURL.path] + args
        process.currentDirectoryURL = engineDir

        // Inherit environment, but make python behavior deterministic.
        var env = ProcessInfo.processInfo.environment
        env["PYTHONUNBUFFERED"] = "1"
        env["PYTHONNOUSERSITE"] = "1"

        // When using a bundled runtime, setting PYTHONHOME makes stdlib resolution more reliable
        // (especially under App Translocation / different launch contexts).
        if let home = python.pythonHome {
            env["PYTHONHOME"] = home.path
        }

        if let site = try? bundledSitePackagesPath(pythonHome: python.pythonHome) {
            // Prepend bundled site-packages so imports resolve when using a bundled runtime.
            if let existing = env["PYTHONPATH"], !existing.isEmpty {
                env["PYTHONPATH"] = site + ":" + existing
            } else {
                env["PYTHONPATH"] = site
            }
        }

        // Keep bytecode caching enabled, but force pyc output outside the app bundle.
        let pycachePrefix = try pythonBytecodeCachePrefixDirectory()
        env["PYTHONPYCACHEPREFIX"] = pycachePrefix.path
#if DEBUG
        print("[PythonRunner] PYTHONPYCACHEPREFIX=\(pycachePrefix.path)")
#endif

        process.environment = env

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // Incremental capture to avoid deadlocks on large outputs.
        let stdoutHandle = stdoutPipe.fileHandleForReading
        let stderrHandle = stderrPipe.fileHandleForReading
        var stdoutData = Data()
        var stderrData = Data()

        let stdoutQueue = DispatchQueue(label: "pythonrunner.stdout")
        let stderrQueue = DispatchQueue(label: "pythonrunner.stderr")

        stdoutHandle.readabilityHandler = { handle in
            let chunk = handle.availableData
            if !chunk.isEmpty {
                stdoutQueue.sync { stdoutData.append(chunk) }
            }
        }

        stderrHandle.readabilityHandler = { handle in
            let chunk = handle.availableData
            if !chunk.isEmpty {
                stderrQueue.sync { stderrData.append(chunk) }
            }
        }

        let done = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            done.signal()
        }

        do {
            try process.run()
        } catch {
            // Stop handlers before rethrow.
            stdoutHandle.readabilityHandler = nil
            stderrHandle.readabilityHandler = nil
            throw error
        }

        // Wait with timeout
        let waitResult = done.wait(timeout: .now() + effectiveTimeout)
        if waitResult == .timedOut {
            process.terminate()
            _ = done.wait(timeout: .now() + 5) // brief grace period

            stdoutHandle.readabilityHandler = nil
            stderrHandle.readabilityHandler = nil

            let out = String(data: stdoutData, encoding: .utf8) ?? ""
            let err = String(data: stderrData, encoding: .utf8) ?? ""
            throw PythonRunnerError.runtimeError(
                "Python command timed out after \(Int(effectiveTimeout))s.\nArgs: \(redactedArgsString(args))\n\nSTDERR:\n\(err)\n\nSTDOUT:\n\(out)"
            )
        }

        // Stop handlers now that process is done.
        stdoutHandle.readabilityHandler = nil
        stderrHandle.readabilityHandler = nil

        // Ensure we drain any remaining data.
        stdoutQueue.sync {
            let remainder = stdoutHandle.readDataToEndOfFile()
            if !remainder.isEmpty { stdoutData.append(remainder) }
        }
        stderrQueue.sync {
            let remainder = stderrHandle.readDataToEndOfFile()
            if !remainder.isEmpty { stderrData.append(remainder) }
        }

        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
            let message = stderr.isEmpty ? stdout : stderr
            throw PythonRunnerError.runtimeError(
                "Python exited with code \(process.terminationStatus).\nArgs: \(redactedArgsString(args))\n\n\(message)"
            )
        }

        return stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Errors thrown by PythonRunner.
enum PythonRunnerError: LocalizedError {
    case runtimeError(String)

    var errorDescription: String? {
        switch self {
        case .runtimeError(let message):
            return message
        }
    }
}

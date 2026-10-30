import Foundation

/// Runs command-line tools. GUI apps don't inherit the shell PATH, so we set a sensible one.
enum Shell {
    struct Result {
        let code: Int32
        let out: String
        let err: String
        var ok: Bool { code == 0 }
    }

    static let home = FileManager.default.homeDirectoryForCurrentUser.path

    static let path: String = [
        "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin",
        home + "/.docker/bin", "/Applications/Docker.app/Contents/Resources/bin",
        home + "/.local/bin", home + "/Library/Android/sdk/platform-tools"
    ].joined(separator: ":")

    /// Resolves a tool name on our PATH. Returns nil when it isn't installed.
    static func which(_ name: String) -> String? {
        if name.hasPrefix("/") { return FileManager.default.isExecutableFile(atPath: name) ? name : nil }
        for dir in path.split(separator: ":") {
            let p = "\(dir)/\(name)"
            if FileManager.default.isExecutableFile(atPath: p) { return p }
        }
        return nil
    }

    @discardableResult
    static func run(_ tool: String, _ args: [String], cwd: String? = nil, timeout: TimeInterval = 30, input: String? = nil) -> Result {
        guard let exe = which(tool) else { return Result(code: 127, out: "", err: "\(tool) not found") }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        if let cwd { p.currentDirectoryURL = URL(fileURLWithPath: cwd) }
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = path
        env["GIT_TERMINAL_PROMPT"] = "0"
        p.environment = env
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        if let input {
            let inPipe = Pipe()
            p.standardInput = inPipe
            inPipe.fileHandleForWriting.write(input.data(using: .utf8) ?? Data())
            try? inPipe.fileHandleForWriting.close()
        } else {
            p.standardInput = FileHandle.nullDevice
        }
        do { try p.run() } catch { return Result(code: -1, out: "", err: error.localizedDescription) }

        // Read both pipes concurrently so a full stderr buffer can't block stdout.
        var errData = Data()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            errData = err.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        let timer = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        p.waitUntilExit()
        timer.cancel()
        return Result(code: p.terminationStatus,
                      out: String(decoding: outData, as: UTF8.self),
                      err: String(decoding: errData, as: UTF8.self))
    }

    /// Starts a command detached from us, logging to ~/Library/Logs/SpawnSweep. Used for Relaunch.
    static func launchDetached(_ command: String, cwd: String) -> Bool {
        let logDir = home + "/Library/Logs/SpawnSweep"
        try? FileManager.default.createDirectory(atPath: logDir, withIntermediateDirectories: true)
        let log = "\(logDir)/relaunch-\(Int(Date().timeIntervalSince1970)).log"
        let script = "cd \(quote(cwd)) && nohup \(command) > \(quote(log)) 2>&1 &"
        return run("/bin/zsh", ["-lc", script], timeout: 10).ok
    }

    static func quote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    /// Disk usage in bytes, following `du -sk`. Slow on big trees; call off the main thread.
    /// `excluding` skips folders by name anywhere below `path` (du -I), e.g. places macOS would ask permission for.
    static func du(_ path: String, excluding: [String] = [], timeout: TimeInterval = 120) -> Int64? {
        let r = run("/usr/bin/du", ["-sk"] + excluding.flatMap { ["-I", $0] } + [path], timeout: timeout)
        guard let kb = Int64(r.out.split(separator: "\t").first?.trimmingCharacters(in: .whitespaces) ?? "") else { return nil }
        return kb * 1024
    }
}

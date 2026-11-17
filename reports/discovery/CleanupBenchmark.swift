import Foundation
import Darwin

/// Compiled only in the disposable source checkout made by benchmark-cleanup.sh.
enum CleanupBenchmark {
    private struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    static func run() {
        let arguments = CommandLine.arguments
        do {
            guard arguments.count == 6 else { throw Failure(description: "Expected four fixture arguments.") }
            try measure(repo: arguments[2], tree: arguments[3], python: arguments[4], run: arguments[5])
        } catch {
            FileHandle.standardError.write(Data("Cleanup fixture failed: \(error)\n".utf8))
            exit(1)
        }
    }

    private static func measure(repo: String, tree: String, python: String, run: String) throws {
        let fileManager = FileManager.default
        let worktrees = DiskScanner.worktrees(of: repo)
        guard worktrees.count == 1, var worktree = worktrees.first, worktree.path == tree, worktree.agent == .codex,
              tree.hasSuffix("/.codex/worktrees/finished-task"),
              ProcessInfo.processInfo.environment["SPAWNSWEEP_FIXTURE_TREE"] == tree else {
            throw Failure(description: "Expected the single synthetic Codex worktree created by the benchmark runner.")
        }

        worktree.defaultBranch = "main"
        worktree.status = DiskScanner.status(worktree, busy: [])
        worktree.slimDirs = DiskScanner.slimCandidates(tree)
        let dependencies = tree + "/node_modules"
        let envFixture = tree + "/.env"
        let sourceFixture = tree + "/app.js"
        let initialSource = try Data(contentsOf: URL(fileURLWithPath: sourceFixture))
        let initialEnv = try Data(contentsOf: URL(fileURLWithPath: envFixture))
        guard worktree.status == .merged, worktree.slimDirs == [dependencies], let initialSize = Shell.du(tree) else {
            throw Failure(description: "The worktree is missing its merged branch or ignored dependencies.")
        }

        let server = Process()
        server.executableURL = URL(fileURLWithPath: python)
        server.currentDirectoryURL = URL(fileURLWithPath: tree)
        server.arguments = ["-I", "-c", """
            from http.server import BaseHTTPRequestHandler, HTTPServer
            HTTPServer(('127.0.0.1', 0), BaseHTTPRequestHandler).serve_forever()
            """]
        try server.run()
        defer {
            if server.isRunning { server.terminate() }
            server.waitUntilExit()
        }

        let pid = server.processIdentifier
        let listener = (0..<20).lazy.compactMap { _ in
            Thread.sleep(forTimeInterval: 0.05)
            return ProcessTable.listeners().first { $0.pid == pid && $0.host == "127.0.0.1" }
        }.first
        guard server.isRunning, let listener, let processStart = ProcessTable.startTime(pid) else {
            throw Failure(description: "The disposable loopback server did not start.")
        }

        let start = ProcessInfo.processInfo.systemUptime
        let process = Actions.stopProcesses([ProcRef(pid: pid, start: processStart)])
        guard process.stopped == 1, process.failed.isEmpty, !server.isRunning else {
            throw Failure(description: "The disposable loopback process did not stop.")
        }
        let disk = Actions.slim(worktree)
        let elapsed = (ProcessInfo.processInfo.systemUptime - start) * 1_000
        guard disk.failures.isEmpty, !fileManager.fileExists(atPath: dependencies),
              let finalSize = Shell.du(tree), initialSize - finalSize == disk.freedDisk,
              try Data(contentsOf: URL(fileURLWithPath: sourceFixture)) == initialSource,
              try Data(contentsOf: URL(fileURLWithPath: envFixture)) == initialEnv,
              !ProcessTable.listeners().contains(where: { $0.port == listener.port }) else {
            throw Failure(description: "Failed to verify the port, reclaimed bytes, or preservation of source and .env.")
        }
        print([run, String(worktrees.count), String(process.stopped), "1", String(disk.freedDisk), String(format: "%.1f", elapsed)].joined(separator: ","))
    }
}

import Foundation

/// The small surface Ensembyte needs of omp (oh-my-pi, `omp`, https://omp.sh): whether
/// it is signed in, its model catalog, and the two files Ensembyte installs for its
/// sessions.
///
/// omp keeps its logins in `~/.omp/agent/agent.db`, a database nothing outside omp
/// should read, so the CLI is asked instead: `omp models --json` lists the models of
/// every provider omp can use right now, and an empty list means nothing is signed in.
enum OmpCLI {
    /// omp's `--thinking` levels, which Ensembyte's effort strings map to 1:1. omp has an
    /// `auto` of its own that the effort slider does not offer.
    static let thinkingLevels = ["off", "minimal", "low", "medium", "high", "xhigh", "max"]

    /// Where the MCP extension and the settings file live.
    static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: LoginEnvironment.homeDirectory).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("\(AppInfo.name)/omp", isDirectory: true)
    }

    /// Distinct provider names with at least one usable model, else signed out; unknown
    /// when omp could not be asked.
    static func authStatus(executable: URL, environment: [String: String]) async -> ProviderStatus.Auth {
        guard let models = try? await catalog(executable: executable, environment: environment) else { return .unknown }
        let providers = Set(models.compactMap { $0["provider"]?.string }).sorted()
        return providers.isEmpty ? .signedOut : .signedIn(providers.joined(separator: ", "))
    }

    /// The chat models omp can use, with the model omp itself is set to marked as the default.
    static func listModels(executable: URL, environment: [String: String]) async throws -> [ModelOption] {
        async let current = currentModel(executable: executable, environment: environment)
        let items = try await catalog(executable: executable, environment: environment)
        let currentSelector = await current
        var options: [ModelOption] = []
        for item in items {
            guard let provider = item["provider"]?.string, let id = item["id"]?.string else { continue }
            let fullID = "\(provider)/\(id)"
            // The model's own effort levels; a model that does not reason has none.
            let efforts = (item["thinking"]?.array ?? []).compactMap(\.string)
            options.append(ModelOption(
                id: fullID,
                name: item["name"]?.string ?? id,
                detail: provider,
                efforts: efforts,
                defaultEffort: efforts.contains("medium") ? "medium" : efforts.first,
                isDefault: fullID == currentSelector
            ))
        }
        guard !options.isEmpty else {
            throw ProviderError.failed("omp listed no models.")
        }
        return options.sorted { ($0.detail ?? "", $0.name) < ($1.detail ?? "", $1.name) }
    }

    /// `omp models --json`: no session and no frame size limit, unlike the same list over RPC.
    private static func catalog(executable: URL, environment: [String: String]) async throws -> [JSONValue] {
        let home = environment["HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? LoginEnvironment.homeDirectory
        let result = try await Shell.run(
            executable,
            ["models", "--json", "--no-extensions"],
            in: URL(fileURLWithPath: home),
            environment: environment,
            timeout: 30
        )
        guard result.succeeded, let models = JSONValue.parse(result.stdout)?["models"]?.array else {
            throw ProviderError.failed("omp could not list its models. \(result.failureMessage)")
        }
        return models
    }

    /// `provider/id` of the model omp starts on, from a throwaway `omp --mode rpc` process.
    private static func currentModel(executable: URL, environment: [String: String]) async -> String? {
        let home = environment["HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? LoginEnvironment.homeDirectory
        let process = StdioProcess(
            executable: executable,
            arguments: ["--mode", "rpc", "--no-session", "--no-extensions", "--no-skills", "--no-rules"],
            directory: URL(fileURLWithPath: home),
            environment: environment,
            framing: .lines
        )
        do {
            try process.start()
        } catch {
            return nil
        }
        process.send(["type": "get_state", "id": "state"])
        let timeout = Task {
            try? await Task.sleep(for: .seconds(20))
            process.terminate()
        }
        var selector: String?
        for await message in process.messages where message["id"]?.string == "state" {
            if let model = (message["data"] ?? message)["model"],
               let provider = model["provider"]?.string, let id = model["id"]?.string {
                selector = "\(provider)/\(id)"
            }
            break
        }
        timeout.cancel()
        process.terminate()
        return selector
    }

    // MARK: - Installed files

    /// Writes `text` into the support directory and returns its path. Rewritten only when
    /// the text changed, so a new build's file replaces the old one.
    private static func install(_ name: String, _ text: String) throws -> URL {
        let directory = supportDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent(name)
        let data = Data(text.utf8)
        if (try? Data(contentsOf: file)) != data {
            try data.write(to: file, options: .atomic)
        }
        return file
    }

    /// The settings overlay one session runs with (`--config`), a file of its own because
    /// the team a chat leads is its own.
    ///
    /// A shell command or a subagent that runs long is moved to the background by omp, and
    /// its result wakes the agent again with a turn nobody asked for and the app never saw
    /// begin (`bash.autoBackground`, and `async`, which covers `task`); here they are waited
    /// for, as they are for every other provider. Hydra heads never run as omp subagents: they
    /// are Ensembyte-run threads, and the gate (`extensionSource`) keeps the `task` tool closed.
    ///
    /// A chat is one omp session, and the app names it by path when it resumes one (`--resume`).
    /// A launch with no path is a new conversation, which omp would not start if the user's own
    /// config has `autoResume` on: it continues the folder's latest session instead, so a new
    /// chat in a project opens with another chat's conversation in it. Off here.
    static func writeLaunchSettings(id: String, hydra: HydraLaunch?, leadModel: String?) throws -> URL {
        let lines = ["autoResume: false", "bash:", "  autoBackground:", "    enabled: false", "async:", "  enabled: false", "task:", "  maxRecursionDepth: 1"]
        let file = try launchDirectory("launch").appendingPathComponent("\(id).yml")
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: file, options: .atomic)
        return file
    }

    /// Where this launch's gate file goes (see `OmpSession.writeGate`); the session writes it.
    static func gateFile(id: String) throws -> URL {
        try launchDirectory("gates").appendingPathComponent("\(id).json")
    }

    /// A folder of files one launch each writes and removes when it stops. A session that
    /// crashed never removed its file, so the ones a day old go.
    private static func launchDirectory(_ name: String) throws -> URL {
        let directory = supportDirectory.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stale = Date.now.addingTimeInterval(-86_400)
        for file in (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [] {
            if let modified = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, modified < stale {
                try? FileManager.default.removeItem(at: file)
            }
        }
        return directory
    }

    /// Writes the gate extension where omp can load it with `-e` and returns its path. Rewritten
    /// only when its text changed, so a new build's extension replaces the old one.
    static func installExtension() throws -> URL {
        try install("ensembyte-gate.ts", extensionSource)
    }

    /// The name of the slash command the gate extension registers. Its presence in omp's command
    /// list is how the session knows the gate loaded; it is no command for the user.
    static let gateCommand = "ensembyte-gate"

    /// The extension Ensembyte loads into every omp session, the mandatory gate for the tools.
    ///
    /// omp's own approval is no gate: a user's `tools.approval.<tool>: allow`, or a rule in
    /// `bash.patterns`, lets a call through whatever mode omp is launched in, and `yolo` (what
    /// Full access runs as) asks nothing at all. This extension sits in front of that. omp
    /// runs every `tool_call` handler before a tool and treats a handler that throws or times
    /// out as a refusal, so a call the gate does not let through never runs, whatever the user
    /// configured. The session reads that the gate loaded (`gateCommand`) and does not start
    /// without it.
    ///
    /// What the gate lets through is the app's word, read from the file named by
    /// `ENSEMBYTE_OMP_GATE` before each call, the way the Pi gate does: a final report blocks
    /// every tool; the `task` tool, which starts subagents that run without asking, runs only
    /// where a Hydra team runs in omp; Plan mode blocks everything that is not a read; Full
    /// access lets the rest through; every other call is asked of the app over `ctx.ui.select`,
    /// which in `rpc-ui` mode reaches the app as an `extension_ui_request` it answers. A tool
    /// the gate does not know is asked about, not let through. A subagent has no one to ask
    /// (`ctx.hasUI` is false), so its calls that are asked about run: a team turned on in a mode
    /// that asks was the user's own word.
    ///
    /// The MCP servers set up in Ensembyte come in here too, as omp tools, through the bridge
    /// the app installs for every provider without MCP support of its own.
    private static let extensionSource = #"""
    import fs from "node:fs";
    import { Type } from "typebox";

    // The tools that only read, or only report back. A tool omp adds later is not one of them.
    const readOnly = new Set(["read", "grep", "glob", "find", "ast_grep", "web_search", "todo", "wait", "think", "ask"]);

    function readGate() {
      try {
        return JSON.parse(fs.readFileSync(process.env.ENSEMBYTE_OMP_GATE || "", "utf8"));
      } catch {
        // Without the app's word nothing is let through unasked.
        return {};
      }
    }

    // `write` to `xd://<tool>` is how omp calls a tool an extension registered: that tool is the call.
    function deviceOf(path) {
      if (typeof path !== "string" || !path.startsWith("xd://")) return undefined;
      return path.slice("xd://".length).split(/[?/#]/)[0] || undefined;
    }

    export default async function (pi) {
      pi.registerCommand("ensembyte-gate", { description: "Ensembyte's tool gate", handler: async () => {} });

      try {
        const bridge = process.env.ENSEMBYTE_MCP_BRIDGE ? await import(process.env.ENSEMBYTE_MCP_BRIDGE) : null;
        if (bridge) {
          for (const tool of await bridge.loadMCPTools()) {
            pi.registerTool({
              name: "mcp__" + tool.server + "__" + tool.name,
              label: tool.server + " · " + tool.name,
              description: tool.description,
              parameters: Type.Unsafe(tool.inputSchema),
              async execute(toolCallId, params) {
                const text = await tool.call(params);
                return { content: [{ type: "text", text }], details: {} };
              },
            });
          }
        }
      } catch (error) {
        console.error("ensembyte mcp: " + (error instanceof Error ? error.message : String(error)));
      }

      pi.on("tool_call", async (event, ctx) => {
        const gate = readGate();
        const device = event.toolName === "write" ? deviceOf(event.input && event.input.path) : undefined;
        const name = device ?? event.toolName;
        // How a subagent hands its work back: nothing to gate.
        if (name === "yield") return;
        if (gate.finalReport) return { block: true, reason: "Declined: this is the final report, with no tools." };
        if (name === "task" && !gate.allowTask) {
          return { block: true, reason: "Declined: subagents are off in this chat, because Hydra is not running its heads in omp." };
        }
        if (readOnly.has(name)) return;
        if (gate.interactionMode === "plan") return { block: true, reason: "Declined: plan mode is read-only." };
        if (gate.runtimeMode === "fullAccess") return;
        if (!ctx.hasUI) return;
        const kind = name === "bash" || name === "eval" ? "command"
          : !device && ["write", "edit", "ast_edit", "notebook"].includes(event.toolName) ? "fileChange" : "tool";
        const input = {};
        for (const [key, value] of Object.entries(event.input || {})) {
          input[key] = typeof value === "string" && value.length > 20000 ? value.slice(0, 20000) : value;
        }
        const payload = { kind, toolName: event.toolName, toolCallId: event.toolCallId, input };
        const answer = await ctx.ui.select("ensembyte-gate " + JSON.stringify(payload), ["Approve", "Deny"]);
        if (answer === "Approve") return;
        return { block: true, reason: "Declined: the user declined this " + (kind === "command" ? "command" : kind === "fileChange" ? "file change" : "tool call") + "." };
      });
    }
    """#
}

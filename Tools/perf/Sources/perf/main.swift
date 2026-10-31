import Foundation

let usage = """
Measures Helio in the iOS simulator against fixture Reddit data. See Tools/perf/README.md.

  perf build <label> [--repo DIR] [--spm DIR]    Release build of a checkout, for testing
  perf bench <label> [--runs N] [--profile]      run the benchmark on that build (default 3 runs)
  perf summary <label>                           medians of the runs
  perf compare <base> <new>                      two labels side by side
  perf check <label> [--budget FILE]             fail if Reddit requests exceed the budget
  perf stalls <label> [--run N] [--from MARK] [--to MARK] [--min-ms MS] [--top N]
  perf callers <label> <symbol> [--run N] [--from MARK] [--to MARK] [--depth N] [--top N]

Results go to $HELIO_PERF_DIR (default $TMPDIR/helio-perf)/<label>. Runs use the simulator in
$HELIO_PERF_SIMULATOR, or a "Helio Perf" iPhone created when missing. Markers: home_open,
scroll_start, scroll_end, post_open, cscroll_start, cscroll_end, end.
"""

/// Positional arguments and `--name value` options (`--profile` takes none).
struct Arguments {
  var positional: [String] = []
  var options: [String: String] = [:]

  init(_ arguments: ArraySlice<String>) {
    var rest = arguments.makeIterator()
    while let argument = rest.next() {
      if argument == "--profile" {
        options["profile"] = "1"
      } else if argument.hasPrefix("--") {
        options[String(argument.dropFirst(2))] = rest.next() ?? ""
      } else {
        positional.append(argument)
      }
    }
  }

  func positional(_ index: Int) -> String {
    guard index < positional.count else { fail("missing argument\n\n\(usage)") }
    return positional[index]
  }

  func int(_ name: String, _ fallback: Int) -> Int {
    options[name].flatMap(Int.init) ?? fallback
  }
}

let commandLine = CommandLine.arguments
guard commandLine.count > 1, !["-h", "--help", "help"].contains(commandLine[1]) else {
  print(usage)
  exit(commandLine.count > 1 ? 0 : 1)
}

let args = Arguments(commandLine.dropFirst(2))
switch commandLine[1] {
case "build":
  Bench.build(label: args.positional(0), repo: args.options["repo"].map { URL(fileURLWithPath: $0) } ?? Paths.repo, spm: args.options["spm"])
case "bench":
  Bench.run(label: args.positional(0), runs: args.int("runs", 3), profile: args.options["profile"] != nil)
case "summary":
  Metrics.printSummary(args.positional(0))
case "compare":
  Metrics.compare(args.positional(0), args.positional(1))
case "check":
  Metrics.check(args.positional(0), budgetFile: args.options["budget"].map { URL(fileURLWithPath: $0) } ?? Paths.tool.appendingPathComponent("budget.json"))
case "stalls":
  Profile.stalls(label: args.positional(0), run: args.int("run", 1), from: args.options["from"] ?? "scroll_start", to: args.options["to"] ?? "scroll_end",
                 minimum: Double(args.options["min-ms"] ?? "") ?? 16, top: args.int("top", 40))
case "callers":
  Profile.callers(label: args.positional(0), run: args.int("run", 1), symbol: args.positional(1), from: args.options["from"] ?? "scroll_start",
                  to: args.options["to"] ?? "scroll_end", depth: args.int("depth", 4), top: args.int("top", 25))
default:
  fail("unknown command \(commandLine[1])\n\n\(usage)")
}

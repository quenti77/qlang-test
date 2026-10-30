--" # qlang-test

Tests that read like sentences. Declare them with `test` / `it` / `describe`, check with
`expect(...)`, and finish the file with a function `qlang test` runs.

```
import describe, it, expect, finish from "@test"

describe("Cart", fun()
  it("adds up the prices", fun()
    expect(total([5, 7])).to_be(12)
  end)

  it("is empty at the start", fun()
    expect(items()).to_have_length(0)
  end)
end)

fun test_suite()
  finish()
end
```

`qlang test` runs `test_suite` (it fails when a case fails); the report shows the groups as a tree,
with the duration of each case, the expected and received values, and the line **of your test**.
Without `qlang test`: end the file with `main()` and run it with `qlang run`.

What there is:

- `test(name, f)` / `it(name, f)`, `describe(name, f)` (nested), `skip`, `only`, `todo(name)`,
  `group(tag, f)` and `QLANG_TEST_GROUP=tag` (or `qlang test --group tag`) to run some groups only.
- `before_all`, `after_all`, `before_each`, `after_each` in a `describe` (or at the top).
- `it_with(name, cases, f)`: one case for each element, named after it (`"valid %s"`).
- `expect(x)` and matchers: `to_be`, `to_equal`, `to_be_greater_than`, `to_be_less_than`,
  `to_be_close_to`, `to_be_true`, `to_be_false`, `to_contain`, `to_have_length`, `to_be_empty`,
  `to_contain_text`, `to_start_with`, `to_end_with`, `to_match` (regex), `to_be_none`, `to_be_some`,
  `to_be_ok`, `to_be_err`, `to_throw`, `to_throw_with`, `to_match_snapshot`, `to_have_been_called`...
  Matchers chain (`expect(n).to_be_greater_than(1).to_be_less_than(10)`) and `never()` turns the next
  ones around (`expect(n).never().to_be(3)`).
- Spies: `spy()` with `fake0` / `fake1` / `fake2` to record the calls of a function.
- Snapshots: `to_match_snapshot()`; `QLANG_UPDATE_SNAPSHOTS=1` writes them.
- Reports for a CI: `QLANG_TEST_JUNIT=report.xml`, `QLANG_TEST_TAP=report.tap`.
--"

-- ------------------------------------------------------------------------ the registry

struct Scope
  public name: string
  public parent: Scope?
  public before_all: array<fun()>
  public after_all: array<fun()>
  public before_each: array<fun()>
  public after_each: array<fun()>
  public started: bool
  public remaining: int
end

struct Case
  public name: string
  public path: array<string>
  public scope: Scope
  public body: fun()
  public mode: string
  public tags: array<string>
end

--" What happened to a case. `status` is `passed`, `failed`, `skipped` or `todo`. --"
struct Outcome
  public path: array<string>
  public name: string
  public status: string
  public ms: int
  public message: string
  public place: string
end

--" The counts of a run. --"
struct Summary
  public passed: int
  public failed: int
  public skipped: int
  public todo: int
  public ms: int
  public outcomes: array<Outcome>
end

struct Registry
  public root: Scope
  public current: Scope
  public cases: array<Case>
  public tags: array<string>
  public running: string
  public snapshot_dir: string
  public snapshot_seen: int
  public allow_new: bool
end

fun new_scope(name: string, parent: Scope?) -> Scope
  Scope { name: name, parent: parent, before_all: [], after_all: [], before_each: [], after_each: [], started: false, remaining: 0 }
end

fun new_registry() -> Registry
  let root = new_scope("", none)
  Registry { root: root, current: root, cases: [], tags: [], running: "", snapshot_dir: "__snapshots__", snapshot_seen: 0, allow_new: false }
end

let registry = new_registry()

--" Forgets every case and hook declared so far (the tests of this package use it). --"
fun reset()
  let fresh = new_registry()
  registry.root = fresh.root
  registry.current = fresh.root
  registry.cases = []
  registry.tags = []
  registry.running = ""
  registry.snapshot_seen = 0
end

--" Where the snapshots are kept (`__snapshots__` by default, from the folder `qlang test` runs in). --"
fun snapshot_dir(path: string)
  registry.snapshot_dir = path
end

--" Saves a snapshot that does not exist yet even when `CI` is set (the default there is to fail, so
that a forgotten snapshot is noticed). --"
fun allow_new_snapshots(on: bool)
  registry.allow_new = on
end

fun path_of(scope: Scope) -> array<string>
  let names: array<string> = []
  let at: Scope? = scope
  while at != none do
    let s = at
    if s.name != "" then
      names.push(s.name)
    end
    at = s.parent
  end
  names.reverse()
  names
end

fun chain_of(scope: Scope) -> array<Scope>
  let chain: array<Scope> = []
  let at: Scope? = scope
  while at != none do
    let s = at
    chain.push(s)
    at = s.parent
  end
  chain.reverse()
  chain
end

fun add_case(name: string, body: fun(), mode: string)
  let scope = registry.current
  let path = path_of(scope)
  path.push(name)
  registry.cases.push(Case { name: name, path: path, scope: scope, body: body, mode: mode, tags: registry.tags.slice(0, registry.tags.len()) })
  for s in chain_of(scope) do
    s.remaining += 1
  end
end

--" A group of cases: `describe` can be nested, and the hooks inside it only concern its cases. --"
fun describe(name: string, body: fun())
  let scope = new_scope(name, registry.current)
  let outer = registry.current
  registry.current = scope
  body()
  registry.current = outer
end

--" A case. --"
fun test(name: string, body: fun())
  add_case(name, body, "run")
end

--" A case (same as `test`, for reading `it("does this", ...)` inside a `describe`). --"
fun it(name: string, body: fun())
  add_case(name, body, "run")
end

--" A case that is declared but not run. --"
fun skip(name: string, body: fun())
  add_case(name, body, "skip")
end

--" Only the cases declared with `only` run (when there are any). --"
fun only(name: string, body: fun())
  add_case(name, body, "only")
end

--" A case to write later: it shows in the report as `todo`. --"
fun todo(name: string)
  add_case(name, fun() end, "todo")
end

--" Tags the cases declared inside (`QLANG_TEST_GROUP=slow` runs only the ones tagged `slow`). --"
fun group(tag: string, body: fun())
  registry.tags.push(tag)
  body()
  registry.tags.pop()
end

--" One case for each element of `cases`, named after it: `%s` in the name is replaced by the
element (`it_with("accepts %s", ["a@b.fr", "x@y.com"], fun(m: string) ... end)`). --"
fun it_with<T>(name: string, cases: array<T>, body: fun(T))
  let i = 0
  for c in cases do
    let shown = "{c}"
    let label = if name.contains("%s") then name.replace("%s", shown) else "{name} [{i}] {shown}" end
    add_case(label, fun() body(c) end, "run")
    i += 1
  end
end

fun before_all(f: fun())
  registry.current.before_all.push(f)
end

fun after_all(f: fun())
  registry.current.after_all.push(f)
end

fun before_each(f: fun())
  registry.current.before_each.push(f)
end

fun after_each(f: fun())
  registry.current.after_each.push(f)
end

-- ------------------------------------------------------------------------ failures

fun fail(message: string)
  panic(message)
end

fun library_place(place: string) -> bool
  place.contains("qlang_test.q") or place.starts_with("<prelude>") or place == ""
end

-- the first place that is not this library: the line of the test
fun test_place(c: Caught) -> string
  for p in c.places do
    if not library_place(p) then
      return p
    end
  end
  ""
end

fun clean_message(m: string) -> string
  if m.starts_with("panic: ") then m.substring(7, m.len()) else m end
end

-- ------------------------------------------------------------------------ running

--" What a run prints and writes. --"
struct Options
  --" `false`: print nothing (the tests of this package read the `Summary`). --"
  public report: bool = true
  --" A JUnit XML file to write ("" : none; `QLANG_TEST_JUNIT` when empty). --"
  public junit: string = ""
  --" A TAP file to write ("" : none; `QLANG_TEST_TAP` when empty). --"
  public tap: string = ""
end

fun split_tags(text: string?) -> array<string>
  let out: array<string> = []
  let t = text ?? ""
  for part in t.split(",") do
    let p = part.trim()
    if p != "" then
      out.push(p)
    end
  end
  out
end

fun wanted(c: Case, only_mode: bool, groups: array<string>, skipped_groups: array<string>) -> bool
  if only_mode and c.mode != "only" then
    return false
  end
  for g in skipped_groups do
    if c.tags.contains(g) then
      return false
    end
  end
  if groups.is_empty() then
    return true
  end
  for g in groups do
    if c.tags.contains(g) then
      return true
    end
  end
  false
end

-- runs the hooks of a list, stopping at the first failure; it gives it
fun run_hooks(hooks: array<fun()>) -> Caught?
  for h in hooks do
    let failure = Panic.guard(h)
    if failure != none then
      return failure
    end
  end
  none
end

fun finish_scope(scope: Scope, extra: array<Outcome>)
  scope.remaining -= 1
  if scope.remaining == 0 and scope.started then
    let failure = run_hooks(scope.after_all)
    if failure != none then
      extra.push(Outcome { path: path_of(scope), name: "after_all", status: "failed", ms: 0, message: clean_message(failure.message), place: test_place(failure) })
    end
  end
end

fun run_case(c: Case, extra: array<Outcome>) -> Outcome
  let started = time.now()
  let chain = chain_of(c.scope)
  let failure: Caught? = none
  let prefix = ""
  registry.running = c.path.join(" > ")
  registry.snapshot_seen = 0
  for s in chain do
    if not s.started then
      s.started = true
      if failure == none then
        failure = run_hooks(s.before_all)
        prefix = "before_all: "
      end
    end
  end
  if failure == none then
    prefix = "before_each: "
    for s in chain do
      if failure == none then
        failure = run_hooks(s.before_each)
      end
    end
  end
  if failure == none then
    prefix = ""
    failure = Panic.guard(c.body)
  end
  -- after_each runs whatever happened; its failure counts when nothing failed before
  let i = chain.len() - 1
  while i >= 0 do
    let late = run_hooks(chain[i].after_each)
    if late != none and failure == none then
      failure = late
      prefix = "after_each: "
    end
    i -= 1
  end
  let j = chain.len() - 1
  while j >= 0 do
    finish_scope(chain[j], extra)
    j -= 1
  end
  let ms = time.now() - started
  if failure == none then
    return Outcome { path: c.path, name: c.name, status: "passed", ms: ms, message: "", place: "" }
  end
  Outcome { path: c.path, name: c.name, status: "failed", ms: ms, message: prefix + clean_message(failure.message), place: test_place(failure) }
end

fun escape_xml(s: string) -> string
  s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;")
end

fun seconds(ms: int) -> string
  let rest = ms % 1000
  let padded = if rest < 10 then "00{rest}" elseif rest < 100 then "0{rest}" else "{rest}" end
  "{ms div 1000}.{padded}"
end

fun junit_text(outcomes: array<Outcome>, ms: int) -> string
  let failures = outcomes.filter(fun(o: Outcome) -> bool o.status == "failed" end).len()
  let skipped = outcomes.filter(fun(o: Outcome) -> bool o.status == "skipped" or o.status == "todo" end).len()
  let lines: array<string> = ["<?xml version=\"1.0\" encoding=\"UTF-8\"?>"]
  lines.push("<testsuite name=\"qlang\" tests=\"{outcomes.len()}\" failures=\"{failures}\" skipped=\"{skipped}\" time=\"{seconds(ms)}\">")
  for o in outcomes do
    let classname = escape_xml(o.path.slice(0, o.path.len() - 1).join("."))
    let head = "  <testcase classname=\"{classname}\" name=\"{escape_xml(o.name)}\" time=\"{seconds(o.ms)}\""
    if o.status == "failed" then
      lines.push(head + ">")
      lines.push("    <failure message=\"{escape_xml(o.message)}\">{escape_xml(o.message)}\n{escape_xml(o.place)}</failure>")
      lines.push("  </testcase>")
    elseif o.status == "skipped" or o.status == "todo" then
      lines.push(head + "><skipped message=\"{o.status}\"/></testcase>")
    else
      lines.push(head + "/>")
    end
  end
  lines.push("</testsuite>")
  lines.join("\n") + "\n"
end

fun tap_text(outcomes: array<Outcome>) -> string
  let lines: array<string> = ["TAP version 13", "1..{outcomes.len()}"]
  let n = 1
  for o in outcomes do
    let label = o.path.join(" > ")
    if o.status == "passed" then
      lines.push("ok {n} - {label}")
    elseif o.status == "failed" then
      lines.push("not ok {n} - {label}")
      lines.push("  ---")
      lines.push("  message: {o.message.replace("\n", " ")}")
      lines.push("  at: {o.place}")
      lines.push("  ...")
    elseif o.status == "todo" then
      lines.push("not ok {n} - {label} # TODO")
    else
      lines.push("ok {n} - {label} # SKIP")
    end
    n += 1
  end
  lines.join("\n") + "\n"
end

fun print_outcome(o: Outcome, shown: array<string>)
  let depth = o.path.len() - 1
  for i in 0..depth do
    if i >= shown.len() or shown[i] != o.path[i] then
      while shown.len() > i do
        shown.pop()
      end
      shown.push(o.path[i])
      print("{"  ".repeat(i)}{o.path[i]}")
    end
  end
  let pad = "  ".repeat(depth)
  if o.status == "passed" then
    print("{pad}ok    {o.name} ({o.ms} ms)")
  elseif o.status == "failed" then
    print("{pad}FAIL  {o.name} ({o.ms} ms)")
    for line in o.message.split("\n") do
      print("{pad}      {line}")
    end
    if o.place != "" then
      print("{pad}      at {o.place}")
    end
  elseif o.status == "todo" then
    print("{pad}todo  {o.name}")
  else
    print("{pad}skip  {o.name}")
  end
end

--" Runs the declared cases and prints the report. `options` chooses what is printed and written. --"
fun run_with(options: Options) -> Summary
  let started = time.now()
  let only_mode = registry.cases.any(fun(c: Case) -> bool c.mode == "only" end)
  let groups = split_tags(env.get("QLANG_TEST_GROUP"))
  let skipped_groups = split_tags(env.get("QLANG_TEST_SKIP_GROUP"))
  let outcomes: array<Outcome> = []
  let shown: array<string> = []
  let passed = 0
  let failed = 0
  let skipped = 0
  let todos = 0
  for c in registry.cases do
    if not wanted(c, only_mode, groups, skipped_groups) then
      continue
    end
    let extra: array<Outcome> = []
    let o = if c.mode == "skip" then
      Outcome { path: c.path, name: c.name, status: "skipped", ms: 0, message: "", place: "" }
    elseif c.mode == "todo" then
      Outcome { path: c.path, name: c.name, status: "todo", ms: 0, message: "", place: "" }
    else
      run_case(c, extra)
    end
    if o.status == "skipped" or o.status == "todo" then
      for s in chain_of(c.scope) do
        s.remaining -= 1
      end
    end
    outcomes.push(o)
    if options.report then
      print_outcome(o, shown)
    end
    for e in extra do
      outcomes.push(e)
      if options.report then
        print_outcome(e, shown)
      end
    end
  end
  for o in outcomes do
    if o.status == "passed" then
      passed += 1
    elseif o.status == "failed" then
      failed += 1
    elseif o.status == "todo" then
      todos += 1
    else
      skipped += 1
    end
  end
  let ms = time.now() - started
  if options.report then
    let extra_text = ""
    if skipped > 0 then
      extra_text += ", {skipped} skipped"
    end
    if todos > 0 then
      extra_text += ", {todos} todo"
    end
    print("\nCases: {passed} passed, {failed} failed{extra_text} ({ms} ms)")
  end
  let junit = if options.junit != "" then options.junit else env.get("QLANG_TEST_JUNIT") ?? "" end
  if junit != "" then
    fs.write(junit, junit_text(outcomes, ms))
  end
  let tap = if options.tap != "" then options.tap else env.get("QLANG_TEST_TAP") ?? "" end
  if tap != "" then
    fs.write(tap, tap_text(outcomes))
  end
  Summary { passed: passed, failed: failed, skipped: skipped, todo: todos, ms: ms, outcomes: outcomes }
end

--" Runs the declared cases and prints the report. --"
fun run() -> Summary
  run_with(Options {})
end

--" Runs the cases, and stops the program with an error when one failed: the body of a
`fun test_suite()` for `qlang test`. --"
fun finish()
  let s = run()
  if s.failed > 0 then
    panic("{s.failed} case(s) failed")
  end
end

--" Runs the cases and ends the program with exit code 1 when one failed: the last line of a file
run with `qlang run`. --"
fun main()
  let s = run()
  if s.failed > 0 then
    exit(1)
  end
end

-- ------------------------------------------------------------------------ expectations

struct Expectation<T>
  public actual: T
  public negated: bool
end

--" Starts a check of `actual`. --"
fun expect<T>(actual: T) -> Expectation<T>
  Expectation<T> { actual: actual, negated: false }
end

fun verdict(holds: bool, negated: bool, positive: string, negative: string)
  if holds == negated then
    fail(if negated then negative else positive end)
  end
end

impl<T> Expectation<T>
  --" The next matchers must NOT hold: `expect(n).never().to_be(3)`. --"
  public fun never(self) -> Expectation<T>
    Expectation<T> { actual: self.actual, negated: not self.negated }
  end
end

impl<T: Eq> Expectation<T>
  --" Equal to `expected`. --"
  public fun to_be(self, expected: T) -> Expectation<T>
    verdict(self.actual == expected, self.negated, "expected {expected}\nreceived {self.actual}", "expected a value other than {expected}")
    self
  end

  --" Same as `to_be`. --"
  public fun to_equal(self, expected: T) -> Expectation<T>
    self.to_be(expected)
  end
end

impl<T: Ord> Expectation<T>
  public fun to_be_greater_than(self, other: T) -> Expectation<T>
    verdict(self.actual > other, self.negated, "expected {self.actual} to be greater than {other}", "expected {self.actual} not to be greater than {other}")
    self
  end

  public fun to_be_less_than(self, other: T) -> Expectation<T>
    verdict(self.actual < other, self.negated, "expected {self.actual} to be less than {other}", "expected {self.actual} not to be less than {other}")
    self
  end

  public fun to_be_at_least(self, other: T) -> Expectation<T>
    verdict(self.actual >= other, self.negated, "expected {self.actual} to be at least {other}", "expected {self.actual} to be less than {other}")
    self
  end

  public fun to_be_at_most(self, other: T) -> Expectation<T>
    verdict(self.actual <= other, self.negated, "expected {self.actual} to be at most {other}", "expected {self.actual} to be more than {other}")
    self
  end
end

impl Expectation<bool>
  public fun to_be_true(self) -> Expectation<bool>
    verdict(self.actual, self.negated, "expected true, received false", "expected false, received true")
    self
  end

  public fun to_be_false(self) -> Expectation<bool>
    verdict(not self.actual, self.negated, "expected false, received true", "expected true, received false")
    self
  end
end

impl Expectation<float>
  --" Within `tolerance` of `expected` (a billionth by default: see `to_be_within`). --"
  public fun to_be_close_to(self, expected: float) -> Expectation<float>
    self.to_be_within(expected, 0.000000001)
  end

  public fun to_be_within(self, expected: float, tolerance: float) -> Expectation<float>
    let diff = if self.actual > expected then self.actual - expected else expected - self.actual end
    verdict(diff <= tolerance, self.negated, "expected {self.actual} to be within {tolerance} of {expected}", "expected {self.actual} not to be within {tolerance} of {expected}")
    self
  end
end

impl<E: Eq> Expectation<array<E>>
  public fun to_contain(self, item: E) -> Expectation<array<E>>
    verdict(self.actual.contains(item), self.negated, "expected {self.actual} to contain {item}", "expected {self.actual} not to contain {item}")
    self
  end

  public fun to_have_length(self, n: int) -> Expectation<array<E>>
    verdict(self.actual.len() == n, self.negated, "expected a length of {n}, received {self.actual.len()}: {self.actual}", "expected a length other than {n}")
    self
  end

  public fun to_be_empty(self) -> Expectation<array<E>>
    verdict(self.actual.is_empty(), self.negated, "expected an empty array, received {self.actual}", "expected an array that is not empty")
    self
  end
end

impl Expectation<string>
  public fun to_contain_text(self, part: string) -> Expectation<string>
    verdict(self.actual.contains(part), self.negated, "expected \"{self.actual}\" to contain \"{part}\"", "expected \"{self.actual}\" not to contain \"{part}\"")
    self
  end

  public fun to_start_with(self, start: string) -> Expectation<string>
    verdict(self.actual.starts_with(start), self.negated, "expected \"{self.actual}\" to start with \"{start}\"", "expected \"{self.actual}\" not to start with \"{start}\"")
    self
  end

  public fun to_end_with(self, end_text: string) -> Expectation<string>
    verdict(self.actual.ends_with(end_text), self.negated, "expected \"{self.actual}\" to end with \"{end_text}\"", "expected \"{self.actual}\" not to end with \"{end_text}\"")
    self
  end

  --" Matches the regular expression `pattern` (anywhere in the text). --"
  public fun to_match(self, pattern: string) -> Expectation<string>
    verdict(regex.matches(self.actual, pattern), self.negated, "expected \"{self.actual}\" to match /{pattern}/", "expected \"{self.actual}\" not to match /{pattern}/")
    self
  end
end

impl<V> Expectation<V?>
  public fun to_be_none(self) -> Expectation<V?>
    verdict(self.actual == none, self.negated, "expected none, received {self.actual}", "expected a value, received none")
    self
  end

  public fun to_be_some(self) -> Expectation<V?>
    verdict(self.actual != none, self.negated, "expected a value, received none", "expected none, received {self.actual}")
    self
  end
end

impl<V, E> Expectation<Result<V, E>>
  public fun to_be_ok(self) -> Expectation<Result<V, E>>
    verdict(self.actual.is_ok(), self.negated, "expected an Ok, received {self.actual}", "expected an Err, received {self.actual}")
    self
  end

  public fun to_be_err(self) -> Expectation<Result<V, E>>
    verdict(self.actual.is_err(), self.negated, "expected an Err, received {self.actual}", "expected an Ok, received {self.actual}")
    self
  end
end

impl Expectation<fun()>
  --" The function fails (a panic, a failed assertion, an `unwrap` of an error...). --"
  public fun to_throw(self) -> Expectation<fun()>
    let failure = Panic.guard(self.actual)
    verdict(failure != none, self.negated, "expected the function to fail, but it finished", "expected the function not to fail")
    self
  end

  --" The function fails with a message that contains `part`. --"
  public fun to_throw_with(self, part: string) -> Expectation<fun()>
    let failure = Panic.guard(self.actual)
    if failure == none then
      verdict(false, self.negated, "expected the function to fail with \"{part}\", but it finished", "")
      return self
    end
    verdict(failure.message.contains(part), self.negated, "expected a failure containing \"{part}\", received \"{failure.message}\"", "expected a failure without \"{part}\"")
    self
  end
end

-- ------------------------------------------------------------------------ spies

--" The calls of a faked function, as the texts of their arguments (`"1, 2"`). --"
struct Spy
  public calls: array<string>
end

--" A new spy. --"
fun spy() -> Spy
  Spy { calls: [] }
end

impl Spy
  public fun times(self) -> int
    self.calls.len()
  end

  public fun last(self) -> string?
    if self.calls.is_empty() then none else self.calls[self.calls.len() - 1] end
  end
end

--" A function that records its calls in `s` and returns what `f` returns. --"
fun fake0<R>(s: Spy, f: fun() -> R) -> fun() -> R
  fun() -> R
    s.calls.push("")
    f()
  end
end

fun fake1<A, R>(s: Spy, f: fun(A) -> R) -> fun(A) -> R
  fun(a: A) -> R
    s.calls.push("{a}")
    f(a)
  end
end

fun fake2<A, B, R>(s: Spy, f: fun(A, B) -> R) -> fun(A, B) -> R
  fun(a: A, b: B) -> R
    s.calls.push("{a}, {b}")
    f(a, b)
  end
end

impl Expectation<Spy>
  public fun to_have_been_called(self) -> Expectation<Spy>
    verdict(self.actual.times() > 0, self.negated, "expected the function to have been called", "expected the function not to have been called, but it was called {self.actual.times()} time(s)")
    self
  end

  public fun to_have_been_called_times(self, n: int) -> Expectation<Spy>
    verdict(self.actual.times() == n, self.negated, "expected {n} call(s), received {self.actual.times()}", "expected a number of calls other than {n}")
    self
  end

  --" One of the calls had these arguments, as text (`"1, 2"`). --"
  public fun to_have_been_called_with(self, args: string) -> Expectation<Spy>
    verdict(self.actual.calls.contains(args), self.negated, "expected a call with ({args}), the calls were {self.actual.calls}", "expected no call with ({args})")
    self
  end
end

-- ------------------------------------------------------------------------ snapshots

fun snapshot_file() -> string
  "{registry.snapshot_dir}/snapshots.snap"
end

fun read_snapshots() -> map<string, string>
  let found: map<string, string> = {}
  let text = fs.read(snapshot_file())
  if text.is_err() then
    return found
  end
  let key = ""
  let body: array<string> = []
  let content = text.unwrap()
  if content.ends_with("\n") then
    content = content.substring(0, content.len() - 1)
  end
  for line in content.split("\n") do
    if line.starts_with("=== ") and line.ends_with(" ===") then
      if key != "" then
        found[key] = body.join("\n")
      end
      key = line.substring(4, line.len() - 4)
      body = []
    elseif key != "" then
      body.push(line)
    end
  end
  if key != "" then
    found[key] = body.join("\n")
  end
  found
end

fun write_snapshots(all: map<string, string>)
  fs.create_dir(registry.snapshot_dir)
  let keys = all.keys()
  keys.sort()
  let parts: array<string> = []
  for k in keys do
    parts.push("=== {k} ===\n{all[k] ?? ""}")
  end
  fs.write(snapshot_file(), parts.join("\n") + "\n")
end

impl<T> Expectation<T>
  --" The value, written as text, is the same as the one saved in `__snapshots__` for this case. The
  first time there is nothing to compare with: it is saved (unless `CI` is set). `QLANG_UPDATE_SNAPSHOTS=1`
  replaces the saved ones. --"
  public fun to_match_snapshot(self) -> Expectation<T>
    registry.snapshot_seen += 1
    let key = "{registry.running} #{registry.snapshot_seen}"
    let now = "{self.actual}"
    let saved = read_snapshots()
    let update = (env.get("QLANG_UPDATE_SNAPSHOTS") ?? "") != ""
    let old = saved[key]
    if old == none then
      if (env.get("CI") ?? "") != "" and not update and not registry.allow_new then
        fail("no snapshot saved for \"{key}\" (run the tests once without CI, or with QLANG_UPDATE_SNAPSHOTS=1)")
      end
      saved[key] = now
      write_snapshots(saved)
      return self
    end
    if update and old != now then
      saved[key] = now
      write_snapshots(saved)
      return self
    end
    verdict(old == now, self.negated, "the snapshot of \"{key}\" differs\nsaved:    {old}\nreceived: {now}", "expected the value to differ from its snapshot")
    self
  end
end

export Outcome, Summary, Options, Expectation, Spy, describe, test, it, skip, only, todo, group, it_with, before_all, after_all, before_each, after_each, run, run_with, finish, main, reset, snapshot_dir, allow_new_snapshots, expect, spy, fake0, fake1, fake2

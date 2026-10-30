import "qlang_test.q" as t

fun quiet() -> t.Summary
  t.run_with(t.Options { report: false })
end

fun status_of(s: t.Summary, name: string) -> string
  for o in s.outcomes do
    if o.name == name then
      return o.status
    end
  end
  "missing"
end

fun test_cases_pass_and_fail_without_stopping_the_others()
  t.reset()
  t.test("passes", fun() t.expect(1 + 1).to_be(2) end)
  t.test("fails", fun() t.expect(1 + 1).to_be(3) end)
  t.test("also passes", fun() t.expect("a").to_equal("a") end)
  let s = quiet()
  assert_eq(s.passed, 2)
  assert_eq(s.failed, 1)
  assert_eq(status_of(s, "fails"), "failed")
  let failed = s.outcomes[1]
  assert(failed.message.contains("expected 3"))
  assert(failed.message.contains("received 2"))
  -- the line is the test's, not the library's
  assert(failed.place.contains("qlang_test_test.q"))
  assert(not failed.place.contains("qlang_test.q:"))
end

fun test_describe_nests_and_hooks_run_in_order()
  t.reset()
  let log: array<string> = []
  t.before_all(fun() log.push("all+") end)
  t.after_all(fun() log.push("all-") end)
  t.before_each(fun() log.push("each+") end)
  t.after_each(fun() log.push("each-") end)
  t.describe("outer", fun()
    t.before_each(fun() log.push("outer+") end)
    t.it("one", fun() log.push("one") end)
    t.describe("inner", fun()
      t.after_each(fun() log.push("inner-") end)
      t.it("two", fun() log.push("two") end)
    end)
  end)
  let s = quiet()
  assert_eq(s.passed, 2)
  assert_eq(log, ["all+", "each+", "outer+", "one", "each-", "each+", "outer+", "two", "inner-", "each-", "all-"])
  assert_eq(s.outcomes[1].path, ["outer", "inner", "two"])
end

fun test_a_failing_hook_fails_the_case_and_the_next_ones_still_run()
  t.reset()
  let n = [0]
  t.describe("g", fun()
    t.before_each(fun()
      n[0] += 1
      if n[0] == 1 then
        panic("setup broke")
      end
    end)
    t.it("first", fun() end)
    t.it("second", fun() end)
  end)
  let s = quiet()
  assert_eq(status_of(s, "first"), "failed")
  assert(s.outcomes[0].message.contains("before_each"))
  assert(s.outcomes[0].message.contains("setup broke"))
  assert_eq(status_of(s, "second"), "passed")
end

fun test_skip_only_todo_and_groups()
  t.reset()
  t.test("normal", fun() end)
  t.skip("skipped", fun() panic("never") end)
  t.todo("later")
  t.group("slow", fun()
    t.test("tagged", fun() end)
  end)
  let s = quiet()
  assert_eq(s.passed, 2)
  assert_eq(s.skipped, 1)
  assert_eq(s.todo, 1)
  t.reset()
  t.test("a", fun() end)
  t.only("b", fun() end)
  let only_run = quiet()
  assert_eq(only_run.passed, 1)
  assert_eq(only_run.outcomes.len(), 1)
  assert_eq(only_run.outcomes[0].name, "b")
end

fun test_it_with_makes_one_named_case_for_each_element()
  t.reset()
  t.it_with("accepts %s", ["a@b.fr", "x@y.com", "bad"], fun(m: string)
    t.expect(m).to_contain_text("@")
  end)
  let s = quiet()
  assert_eq(s.passed, 2)
  assert_eq(s.failed, 1)
  assert_eq(s.outcomes[2].name, "accepts bad")
end

fun fails(f: fun()) -> bool
  Panic.guard(f) != none
end

fun test_the_matchers()
  t.expect(3).to_be_greater_than(2).to_be_less_than(5).to_be_at_least(3).to_be_at_most(3)
  t.expect(3).never().to_be(4)
  t.expect(true).to_be_true()
  t.expect(false).to_be_false()
  t.expect(0.1 + 0.2).to_be_close_to(0.3)
  t.expect(1.0).to_be_within(1.5, 1.0)
  t.expect([1, 2, 3]).to_contain(2).to_have_length(3)
  let none_at_all: array<int> = []
  t.expect(none_at_all).to_be_empty()
  t.expect("hello world").to_contain_text("lo wo").to_start_with("he").to_end_with("ld").to_match("w.r")
  let nothing: int? = none
  let something: int? = 4
  t.expect(nothing).to_be_none()
  t.expect(something).to_be_some()
  let good: Result<int, Error> = Result<int, Error>.Ok(1)
  let bad: Result<int, Error> = Result<int, Error>.Err(Error { message: "x" })
  t.expect(good).to_be_ok()
  t.expect(bad).to_be_err()
  t.expect(fun() panic("boom") end).to_throw().to_throw_with("boom")
  t.expect(fun() end).never().to_throw()
  assert(fails(fun() t.expect(1).to_be(2) end))
  assert(fails(fun() t.expect(2).never().to_be(2) end))
  assert(fails(fun() t.expect([1]).to_contain(5) end))
  assert(fails(fun() t.expect("a").to_match("^b") end))
  assert(fails(fun() t.expect(fun() end).to_throw() end))
  assert(fails(fun() t.expect(fun() panic("boom") end).to_throw_with("other") end))
  assert(fails(fun() t.expect(1.0).to_be_close_to(1.1) end))
end

fun test_failures_say_expected_and_received()
  let failure = Panic.guard(fun() t.expect([1, 2]).to_have_length(3) end)
  let caught = assert_some(failure)
  assert(caught.message.contains("length of 3"))
  assert(caught.message.contains("[1, 2]"))
end

fun test_spies_record_calls()
  let s = t.spy()
  let add = t.fake2(s, fun(a: int, b: int) -> int a + b end)
  assert_eq(add(1, 2), 3)
  add(4, 5)
  t.expect(s).to_have_been_called().to_have_been_called_times(2).to_have_been_called_with("4, 5")
  t.expect(s).never().to_have_been_called_with("9, 9")
  let unused = t.spy()
  t.expect(unused).never().to_have_been_called()
  let one = t.spy()
  let double = t.fake1(one, fun(n: int) -> int n * 2 end)
  assert_eq(double(21), 42)
  assert_eq(one.last(), "21")
end

fun test_snapshots_are_saved_then_compared()
  let dir = "/tmp/qlang-test-snapshots-{time.now()}"
  t.reset()
  t.snapshot_dir(dir)
  t.test("shape", fun() t.expect(["a", "b"]).to_match_snapshot() end)
  assert_eq(quiet().passed, 1)
  assert(assert_ok(fs.exists(dir + "/snapshots.snap")))
  -- same value: still passes; another value: fails
  t.reset()
  t.snapshot_dir(dir)
  t.test("shape", fun() t.expect(["a", "b"]).to_match_snapshot() end)
  assert_eq(quiet().passed, 1)
  t.reset()
  t.snapshot_dir(dir)
  t.test("shape", fun() t.expect(["a", "c"]).to_match_snapshot() end)
  let changed = quiet()
  assert_eq(changed.failed, 1)
  assert(changed.outcomes[0].message.contains("differs"))
end

fun test_junit_and_tap_files_are_written()
  t.reset()
  t.test("ok one", fun() end)
  t.test("bad <one>", fun() t.expect(1).to_be(2) end)
  t.skip("skipped", fun() end)
  let junit = "/tmp/qlang-test-{time.now()}.xml"
  let tap = "/tmp/qlang-test-{time.now()}.tap"
  t.run_with(t.Options { report: false, junit: junit, tap: tap })
  let xml = fs.read(junit).unwrap()
  assert(xml.contains("tests=\"3\" failures=\"1\" skipped=\"1\""))
  assert(xml.contains("name=\"bad &lt;one&gt;\""))
  let text = fs.read(tap).unwrap()
  assert(text.contains("1..3"))
  assert(text.contains("not ok 2 - bad <one>"))
  assert(text.contains("ok 3 - skipped # SKIP"))
end

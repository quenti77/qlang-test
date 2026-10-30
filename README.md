# qlang-test

Tests that read like sentences, for [qlang](https://github.com/quenti77/qlang): `describe` / `it`,
`expect(...).to_be(...)`, hooks, datasets, spies, snapshots, and reports for a CI. Written in qlang,
nothing else to install.

```
qlang add test
```

```
import total from "cart.q"
import describe, it, expect, before_each, finish from "@test"

describe("Cart", fun()
  it("adds up the prices", fun()
    expect(total([5, 7])).to_be(12)
  end)

  describe("with a discount", fun()
    it("never goes below zero", fun()
      expect(total([5]) - 20).to_be_less_than(1)
    end)
  end)
end)

fun test_suite()
  finish()
end
```

```
$ qlang test
Cart
  ok    adds up the prices (1 ms)
  with a discount
    FAIL  never goes below zero (0 ms)
          expected -15 to be greater than -1
          at cart_test.q:11

Cases: 1 passed, 1 failed (2 ms)
```

`finish()` stops with an error when a case failed, which is what makes `qlang test` fail. Without
`qlang test`, end the file with `main()` and `qlang run` it (exit code 1 on a failure). Needs qlang 0.68
(`Panic.guard`).

The failure shows **the line of your test**, not a line of this library.

## What there is

| | |
| --- | --- |
| Cases | `test(name, f)`, `it(name, f)`, `describe(name, f)` (nested), `skip`, `only`, `todo(name)` |
| Hooks | `before_all`, `after_all`, `before_each`, `after_each` (in a `describe`, or at the top) |
| Datasets | `it_with("accepts %s", ["a@b.fr", "x@y.com"], fun(m: string) ... end)`: one case per element, named after it |
| Groups | `group("slow", f)` tags the cases inside; `QLANG_TEST_GROUP=slow` runs those, `QLANG_TEST_SKIP_GROUP=slow` leaves them out |
| Matchers | `to_be`, `to_equal`, `to_be_greater_than`, `to_be_less_than`, `to_be_at_least`, `to_be_at_most`, `to_be_true`, `to_be_false`, `to_be_close_to`, `to_be_within`, `to_contain`, `to_have_length`, `to_be_empty`, `to_contain_text`, `to_start_with`, `to_end_with`, `to_match`, `to_be_none`, `to_be_some`, `to_be_ok`, `to_be_err`, `to_throw`, `to_throw_with`, `to_match_snapshot` |
| Chaining | `expect(n).to_be_greater_than(1).to_be_less_than(10)`; `expect(n).never().to_be(3)` negates the next ones |
| Spies | `let s = spy()`, `fake0(s, f)`, `fake1(s, f)`, `fake2(s, f)`; `expect(s).to_have_been_called_with("1, 2")` |
| Snapshots | `expect(value).to_match_snapshot()` saves in `__snapshots__/snapshots.snap` the first time; `QLANG_UPDATE_SNAPSHOTS=1` replaces; with `CI` set, a missing snapshot fails |
| CI reports | `QLANG_TEST_JUNIT=report.xml`, `QLANG_TEST_TAP=report.tap` (or `run_with(Options { junit: ... })`) |

A failing case never stops the others: each one runs under `Panic.guard`, so a failed matcher, a
`panic`, an `unwrap` of an error or an index out of range is reported against that case. Running out of
steps (`--max-steps`) or memory still stops the run.

## Not there

- **Coverage**: it needs the interpreter to count lines; not done.
- **Test doubles for traits**: `fake0/1/2` replace functions you pass in; there is no automatic fake of a
  trait implementation yet.
- **Removing `fun test_...`**: they keep working, side by side with this package.

## Developing

```
qlang test
```

# Changelog

## 1.0.0

Level **stable**: the public surface of the README (names, signatures, the keys of the JUnit and TAP reports) does not change without the deprecation cycle of qlang (two minor versions between the announcement and the removal). The code is the one of 0.3.0, which passed the qlang 1.12 release without a change.

Breaking: none.

## 0.3.0

The public surface is written down (see the README) and every name of it has a test. Level **provisional**:
nothing in it changes without a "Breaking" line here, and 1.0.0 follows once a qlang minor release has passed with no change.

- The README lists the public surface (name, signature, since which version), the environment variables and the report formats; `reset` is marked internal.
- New tests for `run`, `finish`, `main`, `fake0`, `Spy.times` and `Spy.last`, and for the keys of the JUnit and TAP reports.
- The CI runs the suite on qlang 1.6 (the minimum) and on the latest release.

Breaking: none.

## 0.2.1

`//` replaces `div` (removed in qlang 1.9); the tag compiles again.

## 0.2.0

Trait doubles documented and tested, notes on `--coverage` and `--group`.

## 0.1.0

First version: `describe` / `it`, matchers, hooks, datasets, spies, snapshots, JUnit and TAP reports.

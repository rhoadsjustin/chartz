# Vendored MermaidKit

This is our copy of [MermaidKit](https://github.com/2389-research/MermaidKit),
taken from upstream commit `8556a1b80a1f624d35a4c6e13dcb7a5d427f65c3`
(30 Oct 2026). MIT licensed; see `LICENSE` in this folder, which must stay.

We own this code now and change it freely. It is not a submodule.

## What was kept

`Package.swift`, `Sources/`, `Tests/`, `Fixtures/`, `README.md`,
`CHANGELOG.md`, `LICENSE`.

Left out: the Android, Flutter and Windows bindings, docs, assets, scratchpad,
tools, scripts and CI config. Some tests may refer to files that were left
out; delete or fix those tests as they come up.

## Changes from upstream

- `Package.swift`: added `.tvOS(.v17)` to `platforms`. Not yet built on tvOS.

Add a line here for every change, so pulling in an upstream fix later is a
matter of reading this list.

# Native fixture provenance

The VM extracts the unmodified Tiny Core 16 CorePure64 userspace archive from
https://distro.ibiblio.org/tinycorelinux/16.x/x86_64/release/distribution_files/corepure64.gz
with the SHA-256 digest pinned in tests/core.nix. This archive is byte-identical
to the copies obtained from both official HTTP endpoints. The fixture retains
upstream scripts, binary tools, copyrights and licenses. It supplies Nix and
Python from the outer VM and binds persistent state/data directories; it does
not replace native package-manager or privilege/account tools with stubs.

Original emitter, adapter, tests and shared profile code are MIT. Native Tiny
Core components and application closures retain their upstream licenses.

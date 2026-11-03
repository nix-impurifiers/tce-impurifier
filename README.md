# tce-impurifier

Emit native Tiny Core `.tcz` extensions and boot sets backed by GC-rooted Nix
profiles. Real `tce-load` owns extension mounts, symlinked files and startup
scripts; the shared [engine](https://github.com/nix-impurifiers/impurifier) owns
closure import and `/opt/nix/profile` generations. Original code is MIT.
Application and upstream Tiny Core licenses remain independent.

```nix
let
  impurifier = inputs.tce-impurifier.lib.tce-impurifier {inherit pkgs;};
in impurifier.makeBootSet {
  packages = [
    (impurifier.makeRuntimeTcz {
      nixDependency = "your-native-nix-provider";
      pythonDependency = "python3";
    })
    (impurifier.makeOfflineTcz {pkg=pkgs.hello;})
  ];
}
```

The boot set contains `onboot.lst` and `optional/` with canonical extension names,
`.dep`, `.md5.txt`, `.info`, `.list`, and managed-loader metadata. Add the actual
native Nix/Python provider extensions and other native dependencies to your
repository, or arrange them in the base image. Dependency names are consumer
policy. The native impure Nix provider/installer is deferred, not excluded.
No marker package in the test fixture is an implementation of that installer.

Place the managed artifacts in your native TCE repository and select them through
its normal onboot list; the layout also works with Tiny Core's `/tmp/builtin`
initrd extension mechanism. Preserve `/nix`, the shared engine's
`/var/lib/tce-impurifier` state, `/opt/nix` and application data through your native
mount/backup policy. The default Tiny Core root is ephemeral. Startup restores
declared accounts/directories even if the persistent Nix generation is unchanged;
install/upgrade lifecycle hooks retain their generation semantics.

`makeTcz`, `makeNetTcz`, `makeOfflineTcz` and `makePackage` expose the application
compiler; `makePackage` returns `net` and `offline` output directories. Net/offline
extensions have distinct native names but project the same logical application.
`makeBootSet` rejects duplicate native identities and multiple versions/flavors
of a projected application. `hostDependencies` are plain native extension names;
TCE does not have versioned dependency expressions. Every loaded managed
application records its runtime minimum, which the helper checks before any
reconciliation, including transaction-wide boot startup.

For a new local managed extension, as the normal Tiny Core user:

```sh
tce-impurifier load /path/to/hello-offline.tcz
tce-impurifier reconcile
```

Keep each extension's sidecar files beside it. The wrapper uses actual `tce-load`
and native sudo, then checks activation status. It rejects loading an already
loaded identity or another flavor of a selected application. Native tce-load can
discard startup-script failure statuses; plain native users must inspect its
diagnostics and explicitly reconcile after repair. Boot errors do not turn the
Tiny Core boot process into an atomic OS transaction. Fetch/composition failure
retains the previous published Nix profile; lifecycle failures retain retry state.

**Updates and removal of loaded extensions take effect through boot selection
and reboot.** Native `tce-remove` deliberately refuses loaded extensions. Do not
invent a live unload by deleting individual symlinks. Stage a replacement boot
set atomically and reboot; never overwrite a currently loop-mounted archive in
place. Change the selected flavor in the next boot set rather than mounting both.
Native dependency scanning and tce-setup's deferred startup ordering remain in
use. A changed native driver is captured after boot when declared by an
application; no fake live file-trigger contract is assumed.

The high-level compiler supports CLI programs, declared native libraries, users,
directories, priority and idempotent onInstall/onUpgrade hooks. `/etc`
configuration and service declarations are rejected: Tiny Core's native
configuration backup and service startup are consumer boot policy. It does not
assume OpenRC or systemd is installed. The shared account helper uses actual
shadow tools where present and otherwise BusyBox. `buildTcz` emits lower-level
native payloads for consumer-owned integration; `activate` defaults to false.
License metadata defaults to application SPDX IDs when available and can be
overridden through `license`. Native package ownership does not relicense the
application. Runtime archives retain the shared engine's MIT notice.

`nix flake check -L` runs QEMU with the real pinned Tiny Core 16 userspace,
tce-load, tce-setup, tce-remove, BusyBox, sudo and account tools. The outer kernel
is NixOS. The VM tests runtime minimums, net failure, offline boot recovery,
unchanged-generation account restoration, native refusal of live removal,
application/driver upgrades through actual VM reboots, lifecycle persistence,
GC and boot deselection. Nix/Python are preinstalled and explicitly represented
by a fixture provider. Application data is mounted persistently by the fixture;
this is not a full Tiny Core kernel/init boot or Nix-installer test.

## Native payloads and bundled Nix

`makeNativeTcz { name; version; payload; dependencies?; ... }` emits a native
extension from a producer-prepared tree, without activation scripts or Nix
requirements. Use ordinary native boot sets for selection. The producer supplies
a working target layout; this does not relocate binaries. The VM executes a
static payload in actual Tiny Core userspace without `/nix` or Python, upgrades
its boot set across a QEMU reboot, then checks removal after another reboot.
Tiny Core's native mounted-file symlinks are resolved inside the target root.

`makeRuntimeTcz` optionally accepts `bundledNixStore` and `bundledNixNotices`.
Supply a static ELF client and upstream notices. Bundling omits the default Nix
dependency; Python remains required. Compatible external clients take precedence,
explicit `IMPURIFIER_NIX_STORE` disables fallback, and failed mutations are never
retried through another client. A bundled variant repeats the original boot-set
lifecycle suite with an incompatible external candidate. Nix provisioning remains
deferred, and native extensions still do not claim live unloading.

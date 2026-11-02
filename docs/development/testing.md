# Testing

Run `nix flake check -L`. The VM uses unmodified Tiny Core 16 userspace under the
NixOS kernel, with native tce-load/tce-setup/tce-remove, sudo and BusyBox. Every
boot rebuilds the ephemeral Tiny Core root and binds persistent Nix/profile,
engine and application state. Actual QEMU reboots test onboot selection changes.

The writable Nix store must live on the guest disk. Copy extension sets to the
guest before GC; those are native downloaded artifacts, not Nix GC roots.
Root the base userspace cpio as a VM dependency so subsequent boots can still
extract the OS after collecting unused Nix build artifacts.

Nix/Python are preinstalled. The fixture provider explicitly records that fact.
No native manager/account/privilege executable is mocked. Service and /etc
configuration policy are rejected by the high-level emitter rather than claimed
through a supervisor absent from Tiny Core's base system.

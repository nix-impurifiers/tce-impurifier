# SPDX-License-Identifier: MIT
{ pkgs, impurifier }:
let
  coreImage = import ./core.nix { inherit pkgs; };
  coreCpio = pkgs.runCommand "tinycore16-native.cpio" { nativeBuildInputs = [ pkgs.gzip ]; } ''
    gzip -dc ${coreImage} > $out
  '';
  app =
    version:
    impurifier.makeNativeTcz {
      name = "native-proof";
      inherit version;
      payload = pkgs.runCommand "native-tcz-${version}" { } ''
        mkdir -p $out/usr/local/libexec/native-proof $out/usr/local/share
        cp ${pkgs.pkgsStatic.busybox}/bin/busybox $out/usr/local/libexec/native-proof/busybox
        echo ${version} > $out/usr/local/share/native-proof-version
      '';
    };
  initial = impurifier.makeBootSet { packages = [ (app "1") ]; };
  upgraded = impurifier.makeBootSet { packages = [ (app "2") ]; };
  empty = impurifier.makeBootSet { packages = [ ]; };
in
pkgs.testers.runNixOSTest {
  name = "tce-native-payload";
  requiredFeatures.kvm = false;
  requiredFeatures.devnet = false;
  nodes.machine = { lib, ... }: {
    virtualisation.qemu.package = lib.mkForce pkgs.qemu;
    virtualisation.qemu.forceAccel = false;
    environment.systemPackages = [ pkgs.cpio ];
    boot.kernelModules = [
      "squashfs"
      "loop"
    ];
    system.extraDependencies = [ coreCpio ];
  };
  testScript = ''
    start_all()
    machine.wait_for_unit("multi-user.target")
    machine.succeed("mkdir -p /var/lib/native-sets; cp -rL ${initial} /var/lib/native-sets/one; cp -rL ${upgraded} /var/lib/native-sets/two; cp -rL ${empty} /var/lib/native-sets/empty")
    def prepare(selection):
        machine.succeed("rm -rf /srv/native; mkdir -p /srv/native; cd /srv/native; cpio -idmu --quiet < ${coreCpio}")
        machine.succeed("mkdir -p /srv/native/proc /srv/native/dev /srv/native/sys /srv/native/tmp/builtin /srv/native/tmp/tce/optional /srv/native/home/tc")
        machine.succeed("mount -t proc proc /srv/native/proc; mount --rbind /dev /srv/native/dev; mount --rbind /sys /srv/native/sys; mount --bind /var/lib/native-sets/" + selection + " /srv/native/tmp/builtin")
        machine.succeed("echo tc > /srv/native/etc/sysconfig/tcuser; chown -R 1001:50 /srv/native/home/tc")
        machine.succeed("chroot /srv/native /usr/bin/env PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin TCE=/tce /usr/bin/tce-setup booting")
        machine.succeed("test ! -e /srv/native/nix && test ! -e /srv/native/usr/bin/python3")
    prepare("one")
    machine.succeed("chroot /srv/native /usr/local/libexec/native-proof/busybox echo native-execution | grep native-execution; chroot /srv/native /bin/grep '^1$' /usr/local/share/native-proof-version")
    machine.shutdown()
    machine.start()
    machine.wait_for_unit("multi-user.target")
    prepare("two")
    machine.succeed("chroot /srv/native /bin/grep '^2$' /usr/local/share/native-proof-version")
    machine.shutdown()
    machine.start()
    machine.wait_for_unit("multi-user.target")
    prepare("empty")
    machine.succeed("test ! -e /srv/native/usr/local/libexec/native-proof/busybox && test ! -L /srv/native/usr/local/libexec/native-proof/busybox && test ! -e /srv/native/usr/local/share/native-proof-version && test ! -L /srv/native/usr/local/share/native-proof-version")
  '';
}

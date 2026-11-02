# SPDX-License-Identifier: MIT
{
  pkgs,
  impurifier,
  coreSrc,
}:
let
  coreImage = import ./core.nix { inherit pkgs; };
  coreCpio = pkgs.runCommand "tinycore16.cpio" { nativeBuildInputs = [ pkgs.gzip ]; } ''
    gzip -dc ${coreImage} > $out
  '';
  fixture = import (coreSrc + "/tests/hardware-fixture.nix") { inherit pkgs; };
  tool =
    version:
    pkgs.runCommand "tce-tool-${version}"
      {
        pname = "tce-tool";
        inherit version;
      }
      ''
        mkdir -p $out/bin
        printf '#!${pkgs.busybox}/bin/sh\necho ${version}\n' > $out/bin/tce-tool
        chmod +x $out/bin/tce-tool
      '';
  app =
    offline: version:
    impurifier.makeTcz {
      pkg = tool version;
      inherit offline;
      users.tce-tool = { };
      directories."/var/lib/tce-tool" = {
        owner = "tce-tool:tce-tool";
        mode = "0750";
      };
      lifecycle.onInstall = "echo initialized > /var/lib/tce-tool/initialized";
      lifecycle.onUpgrade = "echo ${version} > /var/lib/tce-tool/migrated";
    };
  provider = impurifier.buildTcz {
    name = "vm-tools";
    version = "1";
    payload = pkgs.runCommand "tce-vm-preinstalled-tools" { } ''
      mkdir -p $out/usr/share/tce-vm
      echo 'Nix and Python are preinstalled in this userspace fixture' > $out/usr/share/tce-vm/tools
    '';
  };
  runtime = impurifier.makeRuntimeTcz {
    nixDependency = "vm-tools";
    pythonDependency = "vm-tools";
  };
  legacy = impurifier.makeRuntimeTcz {
    nixDependency = "vm-tools";
    pythonDependency = "vm-tools";
    version = "0.1";
  };
  driver =
    version:
    impurifier.buildTcz {
      name = "impurifier-host-driver";
      inherit version;
      payload = fixture.driver version;
      dependencies = [ "tce-impurifier" ];
    };
  hardware = impurifier.makeOfflineTcz {
    pkg = fixture.tool;
    inherit (fixture) hardware;
    hostDependencies = [ "impurifier-host-driver" ];
  };
  boot =
    packages:
    impurifier.makeBootSet {
      packages = [
        provider
        runtime
      ]
      ++ packages;
    };
  initial = impurifier.makeBootSet {
    packages = [
      provider
      legacy
    ];
  };
  current = boot [ ];
  offline1 = boot [
    (app true "1")
    (driver "1")
    hardware
  ];
  offline2 = boot [
    (app true "2")
    (driver "2")
    hardware
  ];
  invalidBoot = builtins.tryEval (
    (boot [
      (app true "1")
      (app false "1")
    ]).drvPath
  );
  closure = pkgs.closureInfo { rootPaths = [ offline1 ]; };
in
assert !invalidBoot.success;
{
  contract =
    pkgs.runCommand "tce-impurifier-contract" { nativeBuildInputs = [ pkgs.squashfsTools ]; }
      ''
        unsquashfs -cat ${app true "1"}/tce-tool-offline.tcz usr/local/tce.installed/tce-tool-offline | ${pkgs.bash}/bin/bash -n
        grep -x 'tce-impurifier.tcz' ${app true "1"}/tce-tool-offline.tcz.dep
        grep -x 'NixProvider.tcz' ${
          impurifier.makeRuntimeTcz {
            nixDependency = "NixProvider.tcz";
            pythonDependency = "Python3";
          }
        }/tce-impurifier.tcz.dep
        test "$(wc -l < ${closure}/store-paths)" = 1
        touch $out
      '';
  unit = impurifier.unit;
  vm = pkgs.testers.runNixOSTest {
    name = "tce-impurifier";
    requiredFeatures = {
      kvm = false;
      devnet = false;
    };
    nodes.machine = { lib, ... }: {
      virtualisation.memorySize = 3072;
      virtualisation.diskSize = 6144;
      virtualisation.useNixStoreImage = true;
      virtualisation.writableStore = true;
      virtualisation.writableStoreUseTmpfs = false;
      virtualisation.qemu.package = lib.mkForce pkgs.qemu;
      virtualisation.qemu.forceAccel = false;
      environment.systemPackages = [
        pkgs.nix
        pkgs.python3
        pkgs.cpio
      ];
      boot.kernelModules = [
        "squashfs"
        "loop"
      ];
      system.extraDependencies = [ coreCpio ];
      nix.settings.substituters = lib.mkForce [ ];
    };
    testScript = ''
      start_all()
      machine.wait_for_unit("multi-user.target")
      def prepare_root():
          machine.succeed("rm -rf /srv/core; mkdir -p /srv/core; cd /srv/core; cpio -idmu --quiet < ${coreCpio}")
          machine.succeed("mkdir -p /srv/core/nix /srv/core/proc /srv/core/dev /srv/core/sys /srv/core/opt/nix /srv/core/var/lib/tce-impurifier /srv/core/var/lib/tce-tool /srv/core/tmp/builtin /srv/core/tmp/tce/optional /srv/core/home/tc /opt/nix /var/lib/tce-impurifier /var/lib/tce-vm/app")
          machine.succeed("mount --rbind /nix /srv/core/nix; mount -t proc proc /srv/core/proc; mount --rbind /dev /srv/core/dev; mount --rbind /sys /srv/core/sys; mount --bind /opt/nix /srv/core/opt/nix; mount --bind /var/lib/tce-impurifier /srv/core/var/lib/tce-impurifier; mount --bind /var/lib/tce-vm/app /srv/core/var/lib/tce-tool; mount --bind /var/lib/tce-vm/repo /srv/core/tmp/builtin")
          machine.succeed("echo tc > /srv/core/etc/sysconfig/tcuser; mkdir -p /srv/core/etc/nix; printf 'substituters =\\nbuild-users-group =\\n' > /srv/core/etc/nix/nix.conf; ln -s ${pkgs.nix}/bin/nix-store /srv/core/usr/bin/nix-store; ln -s ${pkgs.python3}/bin/python3 /srv/core/usr/bin/python3")
          machine.succeed("chown -R 1001:50 /srv/core/home/tc /var/lib/tce-vm/repo")
          machine.succeed("systemctl stop dhcpcd; ip link set eth0 down")
      root="chroot /srv/core /usr/bin/env PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin "
      def stage(source):
          machine.succeed("cp -rL " + source + " /var/lib/tce-vm/repo-next; chmod -R u+w /var/lib/tce-vm/repo-next; if test -e /var/lib/tce-vm/repo; then mv /var/lib/tce-vm/repo /var/lib/tce-vm/repo-old; fi; mv /var/lib/tce-vm/repo-next /var/lib/tce-vm/repo")
      def reboot(source):
          machine.succeed("rm -rf /var/lib/tce-vm/repo-old")
          stage(source)
          machine.shutdown()
          machine.start()
          machine.wait_for_unit("multi-user.target")
          prepare_root()
          return machine.execute(root + "TCE=/tce /usr/bin/tce-setup booting 2>&1")
      machine.succeed("mkdir -p /var/lib/tce-vm/sets; cp -rL ${initial} /var/lib/tce-vm/sets/initial; cp -rL ${current} /var/lib/tce-vm/sets/current; cp -rL ${offline1} /var/lib/tce-vm/sets/offline1; cp -rL ${offline2} /var/lib/tce-vm/sets/offline2")
      stage("/var/lib/tce-vm/sets/initial")
      prepare_root()
      machine.succeed(root + "TCE=/tce /usr/bin/tce-setup booting")
      with subtest("native dependency names do not bypass the runtime minimum gate"):
          before=machine.succeed("readlink /opt/nix/profile").strip()
          code, output=machine.execute(root + "/bin/su tc -c '/usr/local/bin/tce-impurifier load ${app true "1"}/tce-tool-offline.tcz' 2>&1")
          assert code != 0 and "native runtime is too old" in output, output
          assert machine.succeed("readlink /opt/nix/profile").strip() == before
          machine.fail("test -e ${builtins.unsafeDiscardStringContext (toString (tool "1"))}")
      with subtest("native loader reports net failure through the adapter"):
          code, output=reboot("/var/lib/tce-vm/sets/current")
          assert code == 0, output
          before=machine.succeed("readlink /opt/nix/profile").strip()
          code, output=machine.execute(root + "/bin/su tc -c '/usr/local/bin/tce-impurifier load ${app false "1"}/tce-tool-net.tcz' 2>&1")
          assert code != 0 and "nix-profile-engine:" in output, output
          assert machine.succeed("readlink /opt/nix/profile").strip() == before
      with subtest("real reboot selects offline closure and native account preparation"):
          code, output=reboot("/var/lib/tce-vm/sets/offline1")
          assert code == 0, output
          machine.succeed(root + "/opt/nix/profile/bin/tce-tool | grep '^1$'")
          machine.succeed(root + "/opt/nix/profile/bin/hardware-tool | grep '^1$'")
          machine.succeed(root + "grep initialized /var/lib/tce-tool/initialized")
          machine.succeed(root + '/usr/bin/python3 -c "import os,pwd; assert os.stat(\'/var/lib/tce-tool\').st_uid == pwd.getpwnam(\'tce-tool\').pw_uid"')
      with subtest("identical boot restores ephemeral accounts without rerunning install hooks"):
          machine.succeed(root + "/bin/sh -c 'echo preserved > /var/lib/tce-tool/initialized'")
          code, output=reboot("/var/lib/tce-vm/sets/offline1")
          assert code == 0, output
          machine.succeed(root + "id tce-tool")
          machine.succeed(root + "grep preserved /var/lib/tce-tool/initialized")
          machine.succeed(root + "/opt/nix/profile/bin/tce-tool | grep '^1$'")
      with subtest("loaded extension removal and live upgrade keep native boot semantics"):
          machine.succeed(root + "/bin/sh -c 'echo /tmp/builtin/optional/tce-tool-offline.tcz > /tmp/audit_marked.lst; tce-remove; test -s /tmp/audit_marked.lst; test -e /tmp/builtin/optional/tce-tool-offline.tcz'")
          code, output=machine.execute(root + "/bin/su tc -c '/usr/local/bin/tce-impurifier load ${app true "2"}/tce-tool-offline.tcz' 2>&1")
          assert code != 0 and "already loaded" in output, output
          machine.succeed(root + "/opt/nix/profile/bin/tce-tool | grep '^1$'")
      with subtest("boot replacement upgrades application and native driver independently"):
          code, output=reboot("/var/lib/tce-vm/sets/offline2")
          assert code == 0, output
          machine.succeed(root + "/opt/nix/profile/bin/tce-tool | grep '^2$'")
          machine.succeed(root + "/opt/nix/profile/bin/hardware-tool | grep '^2$'")
          machine.succeed(root + "grep '^2$' /var/lib/tce-tool/migrated")
          machine.succeed("nix-store --gc")
          machine.succeed(root + "/opt/nix/profile/bin/tce-tool | grep '^2$'")
      with subtest("boot deselection releases profile intent"):
          code, output=reboot("/var/lib/tce-vm/sets/current")
          assert code == 0, output
          machine.fail("test -e /opt/nix/profile/bin/tce-tool")
          machine.fail("test -e /opt/nix/profile/bin/hardware-tool")
          machine.succeed(root + "/usr/sbin/nix-profile-engine prune --keep 0")
          machine.succeed("nix-store --gc")
          machine.fail("test -e ${builtins.unsafeDiscardStringContext (toString (tool "1"))}")
          machine.fail("test -e ${builtins.unsafeDiscardStringContext (toString (tool "2"))}")
    '';
  };
}

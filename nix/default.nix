# SPDX-License-Identifier: MIT
{
  pkgs,
  coreSrc,
  sourceInfo ? { },
}:
let
  inherit (pkgs) lib;
  core = import (coreSrc + "/nix") {
    inherit pkgs;
    namespace = "tce-impurifier";
    sourceInfo = {
      # Native updates must include adapter-only releases, not just engine pins.
      lastModified = pkgs.lib.max (if builtins.isAttrs coreSrc then coreSrc.lastModified or 0 else 0) (
        if builtins.isAttrs sourceInfo then sourceInfo.lastModified or 0 else 0
      );
    };
  };
  validName = value: builtins.match "[A-Za-z0-9][A-Za-z0-9+._-]*" value != null;
  buildTcz =
    {
      name,
      version,
      payload,
      dependencies ? [ ],
      activate ? false,
      projectedName ? null,
      description ? "Impurified Nix application",
      license ? "LicenseRef-Unknown",
      requiredRuntime ? core.runtimeVersion,
    }:
    assert lib.assertMsg (
      validName name && lib.all (d: validName (lib.removeSuffix ".tcz" d)) dependencies
    ) "invalid TCZ package/dependency name";
    assert lib.assertMsg (
      builtins.match "[A-Za-z0-9.+:~_-]+" version != null && builtins.match "[^\n\r]+" description != null
    ) "invalid TCZ metadata";
    assert lib.assertMsg (
      builtins.match "[^\n\r]+" license != null
      && builtins.match "[0-9]+(\\.[0-9]+)*" requiredRuntime != null
    ) "invalid TCZ license or runtime minimum";
    assert lib.assertMsg (
      projectedName == null || validName projectedName
    ) "invalid projected package name";
    pkgs.runCommand "${name}-${version}-tcz"
      {
        nativeBuildInputs = [
          pkgs.squashfsTools
          pkgs.coreutils
        ];
        __structuredAttrs = true;
        unsafeDiscardReferences.out = true;
        passthru = { inherit name version projectedName; };
      }
      ''
        mkdir root "$out"
        cp -r ${payload}/. root/
        chmod -R u+w root
        ${lib.optionalString (projectedName != null) ''
          mkdir -p root/usr/share/tce-impurifier/requirements
          echo '${requiredRuntime}' > root/usr/share/tce-impurifier/requirements/${projectedName}
        ''}
        mkdir -p root/usr/local/tce.installed
        ${lib.optionalString activate ''
          script=root/usr/local/tce.installed/${name}
          printf '#!/bin/sh\nset -eu\n' > "$script"
          ${lib.optionalString (projectedName != null) ''
            digest=$(sha256sum root/usr/share/nix-profile.d/${projectedName}.json | cut -d' ' -f1)
            printf '/usr/sbin/tce-impurifier-activate ${requiredRuntime} ${projectedName} %s\n' "$digest" >> "$script"
          ''}
          ${lib.optionalString (projectedName == null) ''
            echo '/usr/sbin/tce-impurifier-activate ${requiredRuntime}' >> "$script"
          ''}
          ${lib.optionalString (projectedName != null) ''
            # Tiny Core's root is ephemeral. Recreate declared accounts/directories
            # even when an identical persistent Nix generation is already active.
            echo 'if [ -x /usr/lib/tce-impurifier/host/${projectedName} ]; then /usr/lib/tce-impurifier/host/${projectedName}; fi' >> "$script"
          ''}
          chmod 755 "$script"
        ''}
        env -u SOURCE_DATE_EPOCH mksquashfs root "$out/${name}.tcz" -noappend -all-root -all-time 1 -mkfs-time 1 -no-progress -processors 1
        cd "$out"
        md5sum ${name}.tcz > ${name}.tcz.md5.txt
        printf '%s\n' ${
          lib.concatMapStringsSep " " (
            dep: lib.escapeShellArg "${lib.removeSuffix ".tcz" dep}.tcz"
          ) dependencies
        } > ${name}.tcz.dep
        ${lib.optionalString (dependencies == [ ]) "truncate -s 0 ${name}.tcz.dep"}
        cat > ${name}.tcz.info <<'INFO'
        Title:          ${name}.tcz
        Description:    ${description}
        Version:        ${version}
        Copying-policy: ${license}
        INFO
        cat > ${name}.tcz.impurifier.json <<'JSON'
        ${builtins.toJSON {
          schema = 1;
          nativeName = name;
          inherit projectedName;
        }}
        JSON
        unsquashfs -ll ${name}.tcz > ${name}.tcz.list
      '';
  activate = pkgs.writeText "tce-impurifier-activate" ''
    #!/usr/bin/python3
    # SPDX-License-Identifier: MIT
    from pathlib import Path
    import os
    import hashlib
    import sys
    current = Path("/usr/share/tce-impurifier/runtime-version").read_text().strip()
    requirements = [sys.argv[1]] if len(sys.argv) in (2, 4) else ["99999999999999999"]
    requirements += [p.read_text().strip() for p in Path("/usr/share/tce-impurifier/requirements").glob("*")]
    if any(tuple(map(int, current.split("."))) < tuple(map(int, required.split("."))) for required in requirements):
        print("tce-impurifier: native runtime is too old; update the boot set and reboot", file=sys.stderr)
        sys.exit(1)
    if len(sys.argv) == 4:
        actual = hashlib.sha256(Path("/usr/share/nix-profile.d", sys.argv[2] + ".json").read_bytes()).hexdigest()
        if actual != sys.argv[3]:
            print("tce-impurifier: conflicting loaded extension; change the boot selection and reboot", file=sys.stderr)
            sys.exit(1)
    os.execv("/usr/sbin/nix-profile-engine", ["nix-profile-engine", "reconcile"])
  '';
  makeRuntimeTcz =
    {
      bundledNixStore ? null,
      bundledNixNotices ? [ ],
      nixDependency ? (if bundledNixStore == null then "nix" else null),
      pythonDependency ? "python3",
      version ? core.runtimeVersion,
    }:
    buildTcz {
      name = "tce-impurifier";
      inherit version;
      license = "MIT";
      dependencies = lib.optional (nixDependency != null) nixDependency ++ [ pythonDependency ];
      activate = true;
      requiredRuntime = version;
      payload = pkgs.runCommand "tce-impurifier-runtime" { } ''
        mkdir -p $out
        cp -r ${core.makeRuntimeTree { inherit bundledNixStore bundledNixNotices; }}/. $out/
        chmod -R u+w $out
        install -Dm755 ${activate} $out/usr/sbin/tce-impurifier-activate
        install -Dm755 ${../src/adapter.py} $out/usr/local/bin/tce-impurifier
        mkdir -p $out/usr/share/tce-impurifier
        echo '${version}' > $out/usr/share/tce-impurifier/runtime-version
      '';
    };
  makeTcz =
    args@{
      pkg,
      hostDependencies ? [ ],
      license ? null,
      ...
    }:
    assert lib.assertMsg
      (
        (args.configFiles or { }) == { }
        && (args.systemd or null) == null
        && (args.openrc or null) == null
        && (args.runit or null) == null
      )
      "TCZ configuration and service startup remain native host/boot policy; this target supports CLI payloads, accounts, directories and lifecycle hooks";
    let
      payload = core.makePayload (
        (builtins.removeAttrs args [
          "hostDependencies"
          "license"
        ])
        // {
          hostBackend = "openrc";
        }
      );
    in
    buildTcz {
      name = payload.packageName;
      inherit (payload) version description;
      inherit payload;
      activate = true;
      projectedName = payload.name;
      license =
        if license != null then
          license
        else
          let
            values = lib.toList (pkg.meta.license or [ ]);
          in
          if values == [ ] then
            "LicenseRef-Unknown"
          else
            lib.concatMapStringsSep " " (
              v: if builtins.isAttrs v then v.spdxId or "LicenseRef-Unknown" else "LicenseRef-Unknown"
            ) values;
      dependencies = [ "tce-impurifier" ] ++ hostDependencies;
    };
  makeBootSet =
    { packages }:
    let
      names = map (p: p.name) packages;
      projected = map (p: p.projectedName) (lib.filter (p: p.projectedName != null) packages);
    in
    assert lib.assertMsg (
      lib.length names == lib.length (lib.unique names)
      && lib.length projected == lib.length (lib.unique projected)
    ) "duplicate native identity or net/offline application in boot set";
    pkgs.runCommand "tce-impurifier-boot-set"
      {
        __structuredAttrs = true;
        unsafeDiscardReferences.out = true;
      }
      ''
        mkdir -p $out/optional
        ${lib.concatMapStringsSep "\n" (p: "cp ${p}/* $out/optional/") packages}
        cat > $out/onboot.lst <<'ONBOOT'
        ${lib.concatMapStringsSep "\n" (p: "${p.name}.tcz") packages}
        ONBOOT
      '';
  adapter = pkgs.writeScriptBin "tce-impurifier" (
    builtins.replaceStrings [ "#!/usr/bin/python3" ] [ "#!${pkgs.python3}/bin/python3" ] (
      builtins.readFile ../src/adapter.py
    )
  );
in
core
// {
  inherit
    buildTcz
    makeRuntimeTcz
    makeTcz
    makeBootSet
    adapter
    ;
  makeNativeTcz =
    args:
    buildTcz (
      args
      // {
        activate = false;
        projectedName = null;
      }
    );
  runtimeTcz = makeRuntimeTcz { };
  makeNetTcz = args: makeTcz (args // { offline = false; });
  makeOfflineTcz = args: makeTcz (args // { offline = true; });
  makePackage = args: {
    net = makeTcz (args // { offline = false; });
    offline = makeTcz (args // { offline = true; });
  };
}

# SPDX-License-Identifier: MIT
{ ... }:
{ lib, inputs, ... }: {
  flake.lib = lib.mkForce {
    tce-impurifier =
      { pkgs }:
      import ../../../nix {
        inherit pkgs;
        coreSrc = inputs.impurifier;
        sourceInfo = inputs.self;
      };
  };
  perSystem =
    { pkgs, ... }:
    let
      impurifier = import ../../../nix {
        inherit pkgs;
        coreSrc = inputs.impurifier;
        sourceInfo = inputs.self;
      };
    in
    {
      packages = {
        default = impurifier.adapter;
        adapter = impurifier.adapter;
        runtime-tcz = impurifier.runtimeTcz;
        hello-net-tcz = impurifier.makeNetTcz { pkg = pkgs.hello; };
        hello-offline-tcz = impurifier.makeOfflineTcz { pkg = pkgs.hello; };
      };
      formatter = pkgs.nixfmt-tree;
      checks =
        (import ../../../tests {
          inherit pkgs impurifier;
          coreSrc = inputs.impurifier;
        })
        // {
          bundled-vm =
            (import ../../../tests {
              inherit pkgs;
              coreSrc = inputs.impurifier;
              bundled = true;
              impurifier =
                let
                  wrap =
                    args:
                    impurifier.makeRuntimeTcz (
                      args
                      // {
                        bundledNixStore = "${
                          import (inputs.impurifier + "/tests/static-nix.nix") { inherit pkgs; }
                        }/bin/nix-store";
                        bundledNixNotices = [ "${pkgs.nix.src}/COPYING" ];
                      }
                    );
                in
                impurifier
                // {
                  makeRuntimeTcz = wrap;
                  runtimeTcz = wrap { };
                };
            }).vm;
        };
    };
}

# SPDX-License-Identifier: MIT
{ pkgs }:
pkgs.fetchurl {
  urls = [
    "https://distro.ibiblio.org/tinycorelinux/16.x/x86_64/release/distribution_files/corepure64.gz"
    "http://repo.tinycorelinux.net/16.x/x86_64/release/distribution_files/corepure64.gz"
  ];
  hash = "sha256-uhCzdJ5o++Nxw0Idxev/dhgz0x4aSwl+nZYRT83Gvo8=";
}

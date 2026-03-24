{
  description = "A minimal replacement for gettext written in C++";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs?ref=nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";

    tinycmmc.url = "github:grumbel/tinycmmc";
    tinycmmc.inputs.nixpkgs.follows = "nixpkgs";
    tinycmmc.inputs.flake-utils.follows = "flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils, tinycmmc }:
   tinycmmc.lib.eachSystemWithPkgs (pkgs:
     {
        packages = rec {
          default = tinygettext;
          tinygettext = pkgs.callPackage ./tinygettext.nix {
            tinycmmc = tinycmmc.packages.${pkgs.stdenv.hostPlatform.system}.default;
          };
        };
      }
    );
}

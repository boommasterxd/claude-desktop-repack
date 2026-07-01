{
  description = "Claude Desktop for Linux, repackaged from Anthropic's official .deb with minimal Linux patches";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAllSystems (pkgs: rec {
        claude-desktop-repack = pkgs.callPackage ./packaging/nix/package.nix { };
        default = claude-desktop-repack;
      });

      formatter = forAllSystems (pkgs: pkgs.nixpkgs-fmt);
    };
}

{ brewCasks, nixRequiredVersion }:
{ config, pkgs, lib, ... }: let
  cfg = config.brew-nix;
in
with lib; {
  options = {
    brew-nix.enable = mkEnableOption "Activate brew-nix overlay and casks at `pkgs.brewCasks`";
  };

  config = mkIf cfg.enable {
    nixpkgs.overlays = [ brewCasks ];
    nix.package = mkDefault (nixRequiredVersion.package pkgs);

    assertions = [
      {
        assertion = nixRequiredVersion.versionSatisfiesRequirement pkgs config.nix.package;
        message = nixRequiredVersion.message;
      }
    ];
  };
}
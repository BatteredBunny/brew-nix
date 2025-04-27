{ brewCasks }:
{ config, lib, ... }:
let
  cfg = config.brew-nix;
in
{
  options = {
    brew-nix.enable = lib.mkEnableOption "Activate brew-nix overlay and casks at `pkgs.brewCasks`";
  };

  config = lib.mkIf cfg.enable {
    nixpkgs.overlays = [ brewCasks ];
  };
}

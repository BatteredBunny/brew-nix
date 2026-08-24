# Try it against a local brew-nix:
# nix flake check --override-input brew-nix path:../
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nix-darwin = {
      url = "github:nix-darwin/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    brew-nix = {
      url = "github:BatteredBunny/brew-nix";
      inputs.nix-darwin.follows = "nix-darwin";
      inputs.brew-api.follows = "brew-api";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    brew-api = {
      url = "github:BatteredBunny/brew-api";
      flake = false;
    };
  };

  outputs =
    {
      nix-darwin,
      brew-nix,
      ...
    }:
    {
      darwinConfigurations.somehost = nix-darwin.lib.darwinSystem {
        modules = [
          brew-nix.darwinModules.default

          {
            nixpkgs.hostPlatform = "aarch64-darwin";
            system.stateVersion = 6;

            brew-nix.enable = true;
          }

          (
            { pkgs, ... }:
            {
              environment.systemPackages = [
                pkgs.brewCasks.marta
              ];
            }
          )
        ];
      };
    };
}

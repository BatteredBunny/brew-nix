# The `flake.lock` for this flake probably won't work, it's for development,
# better generate your own.
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-24.05-darwin";
    flake-utils.url = "github:numtide/flake-utils";
    nix-darwin = {
      url = "github:LnL7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    brew-nix = {
      # for local testing via `nix flake check` while developing 
      #url = "path:../";
      url = "github:BatteredBunny/brew-nix";
      inputs.nix-darwin.follows = "nix-darwin";
      inputs.brew-api.follows = "brew-api";
      inputs.flake-utils.follows = "flake-utils";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    brew-api = {
      url = "github:BatteredBunny/brew-api";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, nix-darwin, brew-nix, ... }: {
    darwinConfigurations.somehost = nix-darwin.lib.darwinSystem {
      system = "x86_64-darwin";
      modules = [
        brew-nix.darwinModules.default
        ({ pkgs, ... }: {
          brew-nix.enable = true;
          environment.systemPackages = [
            pkgs.brewCasks.marta
          ];
        })
      ];
    };
  };
}

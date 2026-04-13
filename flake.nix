{
  inputs = { nixpkgs.url = "github:nixos/nixpkgs/25.11"; };

  outputs = { self, nixpkgs }:
    let
      supportedSystems =
        [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];

      forEachSupportedSystem = f:
        nixpkgs.lib.genAttrs supportedSystems (system:
          f {
            pkgs = import nixpkgs {
              inherit system;
              config.allowUnfree = true;
            };
          });
    in {
      devShells = forEachSupportedSystem ({ pkgs }: {
        default = pkgs.mkShell {
          packages = with pkgs; [
            vault
            terraform
            ansible
            ansible-lint
            dotnet-sdk_8
            dotnet-runtime_8
            azure-functions-core-tools
            azure-cli
          ];

          shellHook = ''
            export DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1
          '';
        };
      });
    };
}

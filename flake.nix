{
  inputs = { nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable"; };

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
          venvDir = ".venv";
          packages = with pkgs;
            [
              podman
              vault
              terraform
              python313
              ansible
              ansible-lint
              dotnet-sdk_8
              dotnet-runtime_8
              azure-functions-core-tools
              azure-cli
            ] ++ (with python313Packages; [ pip venvShellHook ]);

          shellHook = ''
            export DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1
            unset PYTHONPATH
          '';
        };
      });
    };
}

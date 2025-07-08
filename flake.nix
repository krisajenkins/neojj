{
  description = "NeoJJ - Neovim plugin for Jujutsu VCS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            lua-language-server
            luajitPackages.luacheck
            stylua
            neovim
            git
          ];

          shellHook = ''
            echo "NeoJJ development environment"
            echo "Available tools:"
            echo "  - lua-language-server (type checking)"
            echo "  - luacheck (static analysis)"
            echo "  - stylua (code formatting)"
            echo "  - neovim (testing)"
            echo ""
            echo "Run 'make typecheck' to run all checks"
          '';
        };
      }
    );
}
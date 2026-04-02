final: prev: {
  neovim-unwrapped = prev.neovim-unwrapped.overrideAttrs (oldAttrs: rec {
    version = "0.12.0";

    src = prev.fetchFromGitHub {
      owner = "neovim";
      repo = "neovim";
      rev = "v${version}";
      hash = "sha256-uWhrGAwQ2nnAkyJ46qGkYxJ5K1jtyUIQOAVu3yTlquk=";
    };
  });
}

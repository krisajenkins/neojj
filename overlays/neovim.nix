final: prev: {
  neovim-unwrapped = prev.neovim-unwrapped.overrideAttrs (oldAttrs: rec {
    version = "0.12.3";

    src = prev.fetchFromGitHub {
      owner = "neovim";
      repo = "neovim";
      rev = "v${version}";
      hash = "sha256-JjDU3GZf+wvsMyDjIfu1btTUBkOlpp6E1HFLqBLR9po=";
    };
  });
}

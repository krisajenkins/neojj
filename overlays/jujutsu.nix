final: prev: {
  jujutsu = prev.jujutsu.overrideAttrs (oldAttrs: rec {
    version = "0.40.0";
    src = prev.fetchFromGitHub {
      owner = "jj-vcs";
      repo = "jj";
      rev = "v${version}";
      hash = "sha256-PBrsNHywOUEiFyyHW6J4WHDmLwVWv2JkbHCNvbE0tHE=";
    };
    cargoDeps = prev.rustPlatform.fetchCargoVendor {
      inherit src;
      hash = "sha256-jOklgYw6mYCs/FnTczmkT7MlepNtnHXfFB4lghpLOVE=";
    };

    meta = oldAttrs.meta // {
      description = "Git-compatible VCS (custom version ${version})";
    };
  });
}


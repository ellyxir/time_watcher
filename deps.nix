{ lib, beamPackages, overrides ? (x: y: {}) }:

let
  buildRebar3 = lib.makeOverridable beamPackages.buildRebar3;
  buildMix = lib.makeOverridable beamPackages.buildMix;
  buildErlangMk = lib.makeOverridable beamPackages.buildErlangMk;

  self = packages // (overrides self packages);

  packages = with beamPackages; with self; {
    bunt = buildMix rec {
      name = "bunt";
      version = "1.0.0";

      src = fetchHex {
        pkg = "bunt";
        version = "${version}";
        sha256 = "dc5f86aa08a5f6fa6b8096f0735c4e76d54ae5c9fa2c143e5a1fc7c1cd9bb6b5";
      };

      beamDeps = [];
    };

    credo = buildMix rec {
      name = "credo";
      version = "1.7.16";

      src = fetchHex {
        pkg = "credo";
        version = "${version}";
        sha256 = "d0562af33756b21f248f066a9119e3890722031b6d199f22e3cf95550e4f1579";
      };

      beamDeps = [ bunt file_system jason ];
    };

    dialyxir = buildMix rec {
      name = "dialyxir";
      version = "1.4.7";

      src = fetchHex {
        pkg = "dialyxir";
        version = "${version}";
        sha256 = "b34527202e6eb8cee198efec110996c25c5898f43a4094df157f8d28f27d9efe";
      };

      beamDeps = [ erlex ];
    };

    erlex = buildMix rec {
      name = "erlex";
      version = "0.2.8";

      src = fetchHex {
        pkg = "erlex";
        version = "${version}";
        sha256 = "9d66ff9fedf69e49dc3fd12831e12a8a37b76f8651dd21cd45fcf5561a8a7590";
      };

      beamDeps = [];
    };

    file_system = buildMix rec {
      name = "file_system";
      version = "1.1.1";

      src = fetchHex {
        pkg = "file_system";
        version = "${version}";
        sha256 = "7a15ff97dfe526aeefb090a7a9d3d03aa907e100e262a0f8f7746b78f8f87a5d";
      };

      beamDeps = [];
    };

    jason = buildMix rec {
      name = "jason";
      version = "1.4.4";

      src = fetchHex {
        pkg = "jason";
        version = "${version}";
        sha256 = "c5eb0cab91f094599f94d55bc63409236a8ec69a21a67814529e8d5f6cc90b3b";
      };

      beamDeps = [];
    };
  };
in self


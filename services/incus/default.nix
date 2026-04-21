{ ... }: {
  _class = "clan.service";
  manifest.name = "@juspay/incus";
  manifest.description = "Standalone Incus container daemon with OVS bridge";
  manifest.categories = [ "Infrastructure" ];

  roles.standalone = {
    interface = { lib, ... }: {
      options.useHostNixStore = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Mount host /nix/store into containers via overlay";
      };
    };

    perInstance = { settings, ... }: {
      nixosModule = import ./nixos-module.nix { inherit (settings) useHostNixStore; };
    };
  };
}

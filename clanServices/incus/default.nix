{ ... }: {
  _class = "clan.service";
  manifest.name = "incus";

  roles.standalone = {
    description = "non-clustered incus";
    interface = { lib, ... }: {
      options.useHostNixStore = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Bind mount host /nix/store into containers and use Nix's local-overlay-store experimental feature";
      };
    };

    perInstance = { settings, ... }: {
      nixosModule = import ./nixos-module.nix { inherit (settings) useHostNixStore; };
    };
  };
}

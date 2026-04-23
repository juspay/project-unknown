{ useHostNixStore ? false }:
let
  bridgeName = "incusbr0";
  overlayStore = import ../../common/local-overlay-store.nix;
in
{ lib, ... }: {
  virtualisation.incus = {
    enable = true;
    preseed = {
      networks = [
        {
          name = bridgeName;
          type = "bridge";
          config = {
            "ipv4.address" = "auto";
            "ipv4.nat" = "true";
            "ipv6.address" = "auto";
            "ipv6.nat" = "true";
          };
        }
      ];
      storage_pools = [
        {
          name = "default";
          driver = "btrfs";
          config.source = "/var/lib/incus/storage-pools/default";
        }
      ];
      profiles = [
        {
          name = "default";
          config = lib.optionalAttrs useHostNixStore overlayStore.incusPreseedConfig;
          devices = {
            eth0 = {
              name = "eth0";
              network = bridgeName;
              type = "nic";
            };
            root = {
              path = "/";
              pool = "default";
              type = "disk";
            };
          } // lib.optionalAttrs useHostNixStore overlayStore.incusPreseedDevices;
        }
      ];
    };
  };

  networking.nftables.enable = true;
  networking.firewall.trustedInterfaces = [ bridgeName ];
}

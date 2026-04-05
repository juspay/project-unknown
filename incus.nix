# Incus container daemon — host-side configuration
{ lib, node, ... }:
let
  bridgeName = "incusbr0";
in
{
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
          driver = "dir";
          config = {
            source = "/var/lib/incus/storage-pools/default";
          };
        }
      ];
      profiles = [
        {
          name = "default";
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
          } // (lib.optionalAttrs node.sharedNixStore (import ./local-overlay-store.nix).incusPreseedDevices);
        }
      ];
    };
  };

  networking.nftables.enable = true;
  networking.firewall.trustedInterfaces = [ bridgeName ];
}

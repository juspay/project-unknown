# Incus container daemon — host-side configuration
{ lib, node, ... }:
let
  bridgeName = "incusbr0";
  ovsBridgeName = "ovsbr0";
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
        {
          name = ovsBridgeName;
          type = "bridge";
          config = {
            "bridge.driver" = "openvswitch";
            "ipv4.address" = "10.0.20.1/24";
            "ipv4.nat" = "true";
          };
        }
      ];
      storage_pools = [
        {
          name = "default";
          driver = "btrfs";
          config = {
            source = "/var/lib/incus/storage-pools/default";
          };
        }
      ];
      profiles = [
        {
          name = "default";
          config = lib.optionalAttrs node.useHostNixStore (import ./local-overlay-store.nix).incusPreseedConfig;
          devices = {
            eth0 = {
              name = "eth0";
              network = ovsBridgeName;
              type = "nic";
            };
            root = {
              path = "/";
              pool = "default";
              type = "disk";
            };
          } // (lib.optionalAttrs node.useHostNixStore (import ./local-overlay-store.nix).incusPreseedDevices);
        }
      ];
    };
  };

  virtualisation.vswitch.enable = true;

  networking.nftables.enable = true;
  networking.firewall.trustedInterfaces = [ bridgeName ovsBridgeName ];
}

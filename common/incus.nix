{ lib, node, ... }:
let
  bridgeName = "incusbr0";
  role = (node.incus or {}).role or "standalone";
  isMember = role == "member";
in
{
  virtualisation.incus = {
    enable = true;
    preseed = {
      networks = lib.mkIf (!isMember) [
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

      storage_pools = lib.mkIf (!isMember) [
        {
          name = "default";
          driver = "btrfs";
          config.source = "/var/lib/incus/storage-pools/default";
        }
      ];

      profiles = lib.mkIf (!isMember) [
        {
          name = "default";
          config = lib.optionalAttrs node.useHostNixStore (import ./local-overlay-store.nix).incusPreseedConfig;
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
          } // (lib.optionalAttrs node.useHostNixStore (import ./local-overlay-store.nix).incusPreseedDevices);
        }
      ];
    };
  };

  networking.nftables.enable = true;
  networking.firewall.trustedInterfaces = [ bridgeName ];
}

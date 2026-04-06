# Incus cluster — idliv2-01 is the bootstrap member
{ node, ... }:
{
  virtualisation.incus.preseed.config."core.https_address" = "${node.hostName}.tail12b27.ts.net:8444";
  virtualisation.incus.preseed.cluster = {
    server_name = node.hostName;
    enabled = true;
  };
  networking.firewall.allowedTCPPorts = [ 8444 ];
}

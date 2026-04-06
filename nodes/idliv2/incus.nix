# Incus cluster — network reachability for cluster communication
{ node, ... }:
{
  virtualisation.incus.preseed.config."core.https_address" = "${node.hostName}.tail12b27.ts.net:8444";
  networking.firewall.allowedTCPPorts = [ 8444 ];
}

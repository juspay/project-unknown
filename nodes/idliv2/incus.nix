# Incus cluster — network reachability for cluster communication
{ ... }:
{
  virtualisation.incus.preseed.config."core.https_address" = ":8444";
  networking.firewall.allowedTCPPorts = [ 8444 ];
}

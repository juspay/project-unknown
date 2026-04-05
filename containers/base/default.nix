# Minimal NixOS container image for Incus
{ modulesPath, lib, pkgs, node, ... }:
let
  # Accepts any certificate from the trusted CA
  acceptCAPrincipals = pkgs.writeShellScript "accept-ca-principals" ''
    echo "$1"
  '';
in
{
  imports = [
    "${modulesPath}/virtualisation/lxc-container.nix"
  ] ++ lib.optional node.sharedNixStore (import ../../local-overlay-store.nix).nixosModule;

  environment.etc."ssh/accept-ca-principals" = {
    source = acceptCAPrincipals;
    mode = "0755";
  };

  services.openssh = {
    enable = true;
    extraConfig = ''
      TrustedUserCAKeys ${../../pu-ca.pub}
      AuthorizedPrincipalsCommand /etc/ssh/accept-ca-principals %i
      AuthorizedPrincipalsCommandUser nobody
    '';
    settings.PermitRootLogin = "prohibit-password";
  };

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    sandbox = false;
    substituters = [
      "https://cache.nixos.asia/oss"
      "https://cache.nixos.asia/juspay"
    ];
    trusted-public-keys = [
      "juspay:5aHaNForWL03wKOGhUn/al4BZd3HqZDWZ3hrVTcf6Fg="
      "oss:KO872wNJkCDgmGN3xy9dT89WAhvv13EiKncTtHDItVU="
    ];
    netrc-file = "/etc/nix/netrc";
  };

  environment.systemPackages = with pkgs; [
    vim
    git
    curl
    htop
  ];

  system.stateVersion = "25.11";
}

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
  ] ++ lib.optional node.useHostNixStore (import ../../common/local-overlay-store.nix).nixosModule;

  virtualisation.lxc.templates.hostname = {
    enable = true;
    target = "/etc/hostname";
    template = pkgs.writeText "hostname.tpl" "{{ container.name }}";
    when = [ "create" "copy" ];
  };

  networking.hostName = ""; # To allow lxc's hostname.tpl to take over

  environment.etc."ssh/accept-ca-principals" = {
    source = acceptCAPrincipals;
    mode = "0755";
  };

  services.openssh = {
    enable = true;
    extraConfig = ''
      TrustedUserCAKeys ${../../nodes/idliv2-01/pu-ca.pub}
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

  # When using the host Nix store, UID remapping makes store files appear as
  # nobody:nogroup. OpenSSH refuses to load config files not owned by the
  # running user, so the default Include of the systemd ssh proxy config
  # (which lives in /nix/store) breaks all outbound SSH as root.
  environment.etc."ssh/ssh_config".text = lib.mkForce ''
    Host *
    GlobalKnownHostsFile /etc/ssh/ssh_known_hosts
    StrictHostKeyChecking accept-new
    ForwardX11 no
  '';

  users.users.toor = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
  };

  environment.systemPackages = with pkgs; [
    vim
    git
    curl
    htop
  ];

  system.stateVersion = "25.11";
}

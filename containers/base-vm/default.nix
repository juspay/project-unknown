# Minimal NixOS VM image for KubeVirt
#
# Produces a qcow2 disk image via the kubevirt virtualisation module.
# Feature-set mirrors containers/base (SSH, toor user, basic tools)
# so benchmark comparisons with the Incus container are apples-to-apples.
{ modulesPath, lib, pkgs, ... }:
{
  imports = [
    "${modulesPath}/virtualisation/kubevirt.nix"
  ];

  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "prohibit-password";
  };

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

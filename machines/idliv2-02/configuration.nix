{ ... }:
{
  imports = [
    ../../common/machine.nix
    ../../common/secrets
  ];

  services.openssh.enable = true;

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  system.stateVersion = "25.11";
}

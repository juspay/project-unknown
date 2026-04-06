# NOTE: Don't add anything here. Instead add to `flake.nix`
#
# Also contains some non-hardware config that seldom change
{ node, ... }:
{
  imports =
    [
      ./disko-config.nix
    ];
  hardware.facter.reportPath = ./facter.json;
  networking.hostName = node.hostName;

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  system.stateVersion = "25.05";
}

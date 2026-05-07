{ config, ... }:
{
  nixpkgs.hostPlatform = "x86_64-linux";

  nix.settings = {
    max-jobs = "auto";
    experimental-features = [ "nix-command" "flakes" ];
    trusted-users = [ "root" ];
    substituters = [
      "https://cache.nixos.asia/oss"
      "https://cache.nixos.asia/juspay"
    ];
    trusted-public-keys = [
      "juspay:5aHaNForWL03wKOGhUn/al4BZd3HqZDWZ3hrVTcf6Fg="
      "oss:KO872wNJkCDgmGN3xy9dT89WAhvv13EiKncTtHDItVU="
    ];
    netrc-file = config.clan.core.vars.generators.netrc-juspay.files.netrc.path;
  };

  services.tailscale.enable = true;
}

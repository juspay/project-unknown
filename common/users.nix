# Server users and their permissions
{ node, pkgs, lib, ... }:
let
  inherit (node) admin;
in
{
  users.users."${admin.name}" = {
    isNormalUser = true;
    extraGroups = [ "wheel" "incus-admin" ];

    openssh.authorizedKeys = {
      inherit (admin.openssh.authorizedKeys) keys;
    };
  };

  security = {
    sudo.execWheelOnly = true;
    sudo.wheelNeedsPassword = false;
  };
}

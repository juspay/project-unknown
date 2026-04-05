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

  users.users.pu = {
    isSystemUser = true;
    group = "pu";
    shell = lib.getExe pkgs.bash;
    extraGroups = [ "incus-admin" ];
  } // lib.optionalAttrs (!node.useSSHCA) {
    openssh.authorizedKeys.keys = admin.openssh.authorizedKeys.keys;
  };
  users.groups.pu = {};

  security = {
    sudo.execWheelOnly = true;
    sudo.wheelNeedsPassword = false;
  };
}

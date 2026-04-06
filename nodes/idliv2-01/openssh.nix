{ lib, pkgs, node, ... }:
let
  authLib = if node.useSSHCA
    then ../../pu/lib/identity-cert.sh
    else ../../pu/lib/identity-dev.sh;

  acceptCAPrincipals = pkgs.writeShellScript "accept-ca-principals" ''
    echo "$1"
  '';

  pu-manager = pkgs.writeShellApplication {
    name = "pu-manager";
    runtimeInputs = with pkgs; [ incus coreutils openssh socat gawk gnugrep ];
    text = ''
      ${builtins.readFile authLib}
      ${builtins.readFile ../../pu/lib/incus.sh}
      ${builtins.readFile ../../pu/lib/tcp.sh}
      ${builtins.readFile ../../pu/pu-manager.sh}
    '';
  };
in
{
  environment.etc."ssh/accept-ca-principals" = lib.mkIf node.useSSHCA {
    source = acceptCAPrincipals;
    mode = "0755";
  };

  services.openssh = {
    enable = true;
    extraConfig = lib.mkAfter ''
      Match User pu
        ${lib.optionalString node.useSSHCA "TrustedUserCAKeys ${./pu-ca.pub}"}
        ${lib.optionalString node.useSSHCA "AuthorizedPrincipalsCommand /etc/ssh/accept-ca-principals %i"}
        ${lib.optionalString node.useSSHCA "AuthorizedPrincipalsCommandUser nobody"}
        ${lib.optionalString node.useSSHCA "ExposeAuthInfo yes"}
        ForceCommand ${lib.getExe pu-manager}
        PermitTTY no
        AllowTcpForwarding no
        AllowAgentForwarding no
        X11Forwarding no
    '';
  };
}

{ lib, pkgs, node, ... }:
let
  authEnabled = node.authMode != "none";

  authLib = if authEnabled
    then ./pu/lib/auth-server-cert.sh
    else ./pu/lib/auth-server-none.sh;

  acceptCAPrincipals = pkgs.writeShellScript "accept-ca-principals" ''
    echo "$1"
  '';

  pu-manager = pkgs.writeShellApplication {
    name = "pu-manager";
    runtimeInputs = with pkgs; [ incus coreutils openssh socat gawk gnugrep ];
    text = ''
      ${builtins.readFile authLib}
      ${builtins.readFile ./pu/lib/hypervisor-incus.sh}
      ${builtins.readFile ./pu/lib/tunnel.sh}
      ${builtins.readFile ./pu/pu-manager.sh}
    '';
  };
in
{
  environment.etc."ssh/accept-ca-principals" = lib.mkIf authEnabled {
    source = acceptCAPrincipals;
    mode = "0755";
  };

  services.openssh = {
    enable = true;
    extraConfig = lib.mkAfter ''
      Match User pu
        ${lib.optionalString authEnabled "TrustedUserCAKeys ${./pu-ca.pub}"}
        ${lib.optionalString authEnabled "AuthorizedPrincipalsCommand /etc/ssh/accept-ca-principals %i"}
        ${lib.optionalString authEnabled "AuthorizedPrincipalsCommandUser nobody"}
        ${lib.optionalString authEnabled "ExposeAuthInfo yes"}
        ForceCommand ${lib.getExe pu-manager}
        PermitTTY no
        AllowTcpForwarding no
        AllowAgentForwarding no
        X11Forwarding no
    '';
  };
}

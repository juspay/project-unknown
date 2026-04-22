{ lib, clanLib, ... }: {
  _class = "clan.service";
  manifest.name = "pu";
  manifest.exports.inputs = [ "pki" ];

  roles.manager = {
    description = "pu instance manager — handles container lifecycle and user SSH access";
    interface = { lib, ... }: {
      options = {
        instanceManager = lib.mkOption {
          type = lib.types.enum [ "incus" ];
          default = "incus";
          description = "Backend used to create and manage instances";
        };
        certAuthority = lib.mkOption {
          type = lib.types.nullOr (lib.types.enum [ "step-ca" ]);
          default = null;
          description = "SSH certificate authority provider. null means plain SSH key auth.";
        };
        allowedKeys = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [];
          description = "SSH keys allowed for the pu user when certAuthority is null";
        };
      };
    };

    perInstance = { settings, exports, mkExports, machine, ... }:
    let
      pkiExports = builtins.filter (e: e ? pki) (builtins.attrValues (clanLib.selectExports (_: true) exports));
      pki = if pkiExports == [] then null else (builtins.head pkiExports).pki;
    in {
      nixosModule = { config, pkgs, lib, ... }:
      let
        useCert = settings.certAuthority == "step-ca";

        authLib = if useCert
          then ../../pu/lib/identity-cert.sh
          else ../../pu/lib/identity-dev.sh;

        acceptCAPrincipals = pkgs.writeShellScript "accept-ca-principals" ''
          echo "$1"
        '';

        sshUserCAPubFile = if useCert
          then pkgs.writeText "step-ca-user.pub" pki.sshUserCAPub
          else null;

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
      in {
        assertions = [
          {
            assertion = settings.instanceManager != "incus" || config.virtualisation.incus.enable;
            message = "pu: instanceManager = incus requires the incus clanService on this machine";
          }
          {
            assertion = settings.certAuthority == null || pki != null;
            message = ''
              pu: certAuthority = step-ca but no step-ca instance found in the inventory.
              Add a step-ca instance with roles.server on a machine in inventory.instances.
            '';
          }
        ];

        users.users.pu = {
          isSystemUser = true;
          group = "pu";
          shell = lib.getExe pkgs.bash;
          extraGroups = [ "incus-admin" ];
        } // lib.optionalAttrs (!useCert) {
          openssh.authorizedKeys.keys = settings.allowedKeys;
        };
        users.groups.pu = {};

        environment.etc."ssh/accept-ca-principals" = lib.mkIf useCert {
          source = acceptCAPrincipals;
          mode = "0755";
        };

        services.openssh.extraConfig = lib.mkAfter ''
          Match User pu
            ${lib.optionalString useCert "TrustedUserCAKeys ${sshUserCAPubFile}"}
            ${lib.optionalString useCert "AuthorizedPrincipalsCommand /etc/ssh/accept-ca-principals %i"}
            ${lib.optionalString useCert "AuthorizedPrincipalsCommandUser nobody"}
            ${lib.optionalString useCert "ExposeAuthInfo yes"}
            ForceCommand ${lib.getExe pu-manager}
            PermitTTY no
            AllowTcpForwarding no
            AllowAgentForwarding no
            X11Forwarding no
        '';
      };
    };
  };
}

{ ... }: {
  _class = "clan.service";
  manifest.name = "step-ca";

  roles.server = {
    description = "smallstep certificate authority with SSH signing";
    interface = { lib, ... }: {
      options = {
        name = lib.mkOption {
          type = lib.types.str;
          description = "Name of the certificate authority";
        };
        dns = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          description = "DNS names the CA will be reachable at";
        };
      };
    };

    perInstance = { settings, ... }: {
      nixosModule = { config, pkgs, lib, ... }: {
        clan.core.vars.generators.step-ca = {
          runtimeInputs = [ pkgs.step-cli pkgs.jq ];

          files = {
            root_ca_crt         = { secret = false; };
            intermediate_ca_crt = { secret = false; };
            ssh_user_ca_key_pub = { secret = false; };
            provisioners        = { secret = false; };
            fingerprint         = { secret = false; deploy = false; };

            intermediate_password = { secret = true; owner = "step-ca"; };
            provisioner_password  = { secret = true; deploy = false; };
            root_ca_key           = { secret = true; deploy = false; };
            intermediate_ca_key   = { secret = true; owner = "step-ca"; };
            ssh_host_ca_key       = { secret = true; owner = "step-ca"; };
            ssh_user_ca_key       = { secret = true; owner = "step-ca"; };
          };

          script = ''
            set -euo pipefail

            head -c 32 /dev/urandom | base64 > "$out/intermediate_password"
            head -c 32 /dev/urandom | base64 > "$out/provisioner_password"

            STEPDIR=$(mktemp -d)
            trap 'rm -rf "$STEPDIR"' EXIT
            export STEPPATH="$STEPDIR"

            step ca init \
              --ssh \
              --name ${settings.name} \
              ${lib.concatMapStringsSep " " (d: "--dns ${d}") settings.dns} \
              --address :${builtins.toString config.services.step-ca.port} \
              --password-file "$out/intermediate_password" \
              --provisioner me@shivaraj-bh.in \
              --provisioner-password-file "$out/provisioner_password"

            cp "$STEPDIR/certs/root_ca.crt"         "$out/root_ca_crt"
            cp "$STEPDIR/certs/intermediate_ca.crt"  "$out/intermediate_ca_crt"
            cp "$STEPDIR/certs/ssh_user_ca_key.pub"  "$out/ssh_user_ca_key_pub"
            jq '.authority.provisioners' "$STEPDIR/config/ca.json" > "$out/provisioners"
            step certificate fingerprint "$STEPDIR/certs/root_ca.crt" \
              | tr -d '\n' > "$out/fingerprint"

            cp "$STEPDIR/secrets/root_ca_key"         "$out/root_ca_key"
            cp "$STEPDIR/secrets/intermediate_ca_key" "$out/intermediate_ca_key"
            cp "$STEPDIR/secrets/ssh_host_ca_key"     "$out/ssh_host_ca_key"
            cp "$STEPDIR/secrets/ssh_user_ca_key"     "$out/ssh_user_ca_key"
          '';
        };

        services.step-ca = {
          enable = true;
          address = "0.0.0.0";
          port = 8443;
          openFirewall = true;
          intermediatePasswordFile = config.clan.core.vars.generators.step-ca.files.intermediate_password.path;
          settings = with config.clan.core; {
            root     = vars.generators.step-ca.files.root_ca_crt.path;
            crt      = vars.generators.step-ca.files.intermediate_ca_crt.path;
            key      = vars.generators.step-ca.files.intermediate_ca_key.path;
            dnsNames = settings.dns;
            logger   = { format = "text"; };
            db = {
              type                  = "badgerv2";
              dataSource            = "/var/lib/step-ca/db";
              badgerFileLoadingMode = "";
            };
            tls = {
              cipherSuites = [
                "TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256"
                "TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256"
              ];
              minVersion    = 1.2;
              maxVersion    = 1.3;
              renegotiation = false;
            };
            ssh = {
              hostKey = vars.generators.step-ca.files.ssh_host_ca_key.path;
              userKey = vars.generators.step-ca.files.ssh_user_ca_key.path;
            };
            authority.provisioners =
              builtins.fromJSON (builtins.readFile vars.generators.step-ca.files.provisioners.path);
          };
        };

        systemd.services.step-ca.environment.STEPPATH = "/var/lib/step-ca";
      };
    };
  };
}

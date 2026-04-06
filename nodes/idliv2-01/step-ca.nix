# step-ca certificate authority — OIDC-based SSH certificate signing
#
# One-time setup (run on host):
#   1. sudo -u step-ca STEPPATH=/var/lib/step-ca step ca init --ssh \
#      --name pu \
#      --dns idliv2-01.tail12b27.ts.net \
#      --address :8443
#   2. Copy the ca.json from /var/lib/step-ca/config/ca.json
#   3. Copy pu-ca.pub from /var/lib/step-ca/certs/ssh_user_ca_key.pub
#   4. echo "<password>" > /var/lib/step-ca/intermediate-password  (on host) TODO: replace with secrets manager
#   5. chmod 400 /var/lib/step-ca/intermediate-password (FIXME: maybe not required)
#   6. In the output of (1) you will get fingerprint, replace that in STEP_FINGERPRINT value in flake.nix
{ ... }:
{
  systemd.services.step-ca.environment.STEPPATH = "/var/lib/step-ca";
  services.step-ca = {
    enable = true;
    intermediatePasswordFile = "/var/lib/step-ca/intermediate-password";
    address = "0.0.0.0";
    port = 8443;
    openFirewall = true;
    settings = builtins.fromJSON (builtins.readFile ./ca.json); # See the top of the file for instructions to generate this
    # settings = {
    #   root = "/var/lib/step-ca/certs/root_ca.crt";
    #   crt = "/var/lib/step-ca/certs/intermediate_ca.crt";
    #   key = "/var/lib/step-ca/secrets/intermediate_ca_key";
    #   dnsNames = [ "${outputs.config.hostName}.tail12b27.ts.net" ];
    #   ssh = {
    #     hostKey = "/var/lib/step-ca/secrets/ssh_host_ca_key";
    #     userKey = "/var/lib/step-ca/secrets/ssh_user_ca_key";
    #   };
    #   db = {
    #     type = "badgerv2";
    #     dataSource = "/var/lib/step-ca/db";
    #   };
    #   authority.provisioners = [
    #     {
    #       type = "OIDC";
    #       name = "Google";
    #       clientID = "CHANGEME";
    #       clientSecret = "CHANGEME";
    #       configurationEndpoint = "https://accounts.google.com/.well-known/openid-configuration";
    #     }
    #   ];
    # };
  };
}

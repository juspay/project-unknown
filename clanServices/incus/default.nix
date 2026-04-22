{ ... }: {
  _class = "clan.service";
  manifest.name = "incus";

  roles.bootstrap = {
    description = "First node in an incus cluster; initializes the cluster via preseed";
    interface = { lib, ... }: {
      options = {
        useHostNixStore = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Bind mount host /nix/store into containers and use Nix's local-overlay-store experimental feature";
        };
        clusterAddress = lib.mkOption {
          type = lib.types.str;
          description = "Externally reachable address for this node (used by incus to bind and advertised in join tokens)";
          example = "node1.example.com";
        };
        clusterPort = lib.mkOption {
          type = lib.types.port;
          default = 8443;
          description = "Incus cluster HTTPS API port";
        };
      };
    };

    perInstance = { settings, machine, ... }: {
      nixosModule =
        { ... }:
        {
          imports = [ (import ./standalone.nix { inherit (settings) useHostNixStore; }) ];

          virtualisation.incus.preseed = {
            config."core.https_address" = "${settings.clusterAddress}:${toString settings.clusterPort}";
            cluster = {
              server_name = machine.name;
              enabled = true;
            };
          };

          networking.firewall.allowedTCPPorts = [ settings.clusterPort ];
        };
    };
  };

  roles.member = {
    description = "Incus cluster member that joins an existing bootstrap node";
    interface = { lib, ... }: {
      options = {
        clusterPort = lib.mkOption {
          type = lib.types.port;
          default = 8443;
          description = "Incus cluster HTTPS API port";
        };
      };
    };

    perInstance = { settings, ... }: {
      nixosModule =
        { pkgs, ... }:
        {
          virtualisation.incus.enable = true;
          virtualisation.vswitch.enable = true;
          networking.nftables.enable = true;
          networking.firewall.allowedTCPPorts = [ settings.clusterPort ];
        };
    };
  };
}

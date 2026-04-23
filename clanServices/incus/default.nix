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
        { inputs, pkgs, lib, ... }:
        {
          imports = [ (import ./standalone.nix { inherit (settings) useHostNixStore; }) ];

          virtualisation.incus.preseed = {
            config."core.https_address" = "${settings.clusterAddress}:${toString settings.clusterPort}";
            cluster = {
              server_name = machine.name;
              enabled = true;
            };
          };

          systemd.services.incus-import-container = {
            description = "Import initial NixOS container";
            wantedBy = [ "multi-user.target" ];
            after = [ "incus-preseed.service" ];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
            };
            script = 
              let
                container = inputs.self.nixosConfigurations.base-container;
                metadata = container.config.system.build.metadata;
                squashfs = container.config.system.build.squashfs;
                script = pkgs.writeShellApplication {
                  name = "incus-import-nixos-container";
                  runtimeInputs = [ pkgs.incus ];
                  text = ''
                    incus image delete base-container 2>/dev/null || true
                    echo "Importing container image..."
                    incus image import ${metadata}/tarball/nixos-*.tar.xz ${squashfs}/nixos-lxc-image-x86_64-linux.squashfs --alias base-container
                    echo "Done. Launch with: incus launch base-container <name>"
                  '';
                };
              in ''${lib.getExe script}'';
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
        { inputs, pkgs, lib, ... }:
        {
          virtualisation.incus.enable = true;
          systemd.services.incus-import-container = {
            description = "Import initial NixOS container";
            wantedBy = [ "multi-user.target" ];
            after = [ "incus.service" ];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
            };
            script = 
              let
                container = inputs.self.nixosConfigurations.base-container;
                metadata = container.config.system.build.metadata;
                squashfs = container.config.system.build.squashfs;
                script = pkgs.writeShellApplication {
                  name = "incus-import-nixos-container";
                  runtimeInputs = [ pkgs.incus ];
                  text = ''
                    incus image delete base-container 2>/dev/null || true
                    echo "Importing container image..."
                    incus image import ${metadata}/tarball/nixos-*.tar.xz ${squashfs}/nixos-lxc-image-x86_64-linux.squashfs --alias base-container
                    echo "Done. Launch with: incus launch base-container <name>"
                  '';
                };
              in ''${lib.getExe script}'';
          };
          networking.nftables.enable = true;
          networking.firewall.allowedTCPPorts = [ settings.clusterPort ];
          networking.firewall.trustedInterfaces = [ "incusbr0" ];
        };
    };
  };
}

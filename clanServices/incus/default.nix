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
        { config, inputs, pkgs, lib, ... }:
        let
          inherit (inputs.self.nixosConfigurations.base-container.config.system.build) metadata squashfs;
          apiTxnsFlakeUrl = "git+ssh://git@ssh.bitbucket.juspay.net/jbiz/euler-api-txns.git?ref=staging";

          importImage = pkgs.writeShellApplication {
            name = "incus-import-nixos-container";
            runtimeInputs = [ pkgs.incus ];
            text = ''
              incus image delete base-container || true
              echo "Importing container image..."
              incus image import ${metadata}/tarball/nixos-*.tar.xz ${squashfs}/nixos-lxc-image-x86_64-linux.squashfs --alias base-container
              echo "Done. Launch with: incus launch base-container <name>"
            '';
          };

          refresh = pkgs.writeShellApplication {
            name = "euler-api-txns-refresh";
            runtimeInputs = with pkgs; [ git nix openssh ];
            text = ''
              nix develop '${apiTxnsFlakeUrl}' --refresh -c true
              nix build '${apiTxnsFlakeUrl}#automation-test-nix' --no-link --print-out-paths
            '';
          };

          setupStorage = pkgs.writeShellApplication {
            name = "incus-bootstrap-storage-pool";
            runtimeInputs = [ pkgs.incus ];
            text = ''
              pool="default"
              source="/var/lib/incus/storage-pools/default"
              member="${machine.name}"

              if incus storage show "$pool" >/dev/null 2>&1; then
                current_source="$(incus storage get "$pool" source --target "$member" 2>/dev/null || true)"
                if [ "$current_source" != "$source" ]; then
                  incus storage set "$pool" source "$source" --target "$member"
                fi
                exit 0
              fi

              incus storage create --target "$member" "$pool" btrfs source="$source"
              incus storage create "$pool" btrfs
            '';
          };
        in
        {
          imports = [ (import ./standalone.nix { inherit (settings) useHostNixStore; }) ];

          programs.ssh.extraConfig = ''
            Host ssh.bitbucket.juspay.net
              IdentityFile ${config.clan.core.vars.generators.bitbucket-ssh.files.key.path}
          '';

          virtualisation.incus.preseed = {
            storage_pools = lib.mkForce [ ]; # standalone default is not idempotent for a cluster bootstrap node
            config."core.https_address" = "${settings.clusterAddress}:${toString settings.clusterPort}";
            config."instances.placement.scriptlet" = builtins.readFile ./placement.py;
            cluster = {
              server_name = machine.name;
              enabled = true;
            };
          };

          # Member-specific storage keys are rejected in cluster preseed.
          systemd.services.incus-bootstrap-storage-pool = {
            description = "Create the Incus default storage pool for the bootstrap member";
            after = [ "incus-preseed.service" ];
            requires = [ "incus-preseed.service" ];
            wantedBy = [ "multi-user.target" ];
            serviceConfig.Type = "oneshot";
            script = ''${lib.getExe setupStorage}'';
          };

          systemd.services.incus-import-container = {
            description = "Import initial NixOS container";
            wantedBy = [ "multi-user.target" ];
            after = [ "incus-bootstrap-storage-pool.service" ];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
            };
            script = ''${lib.getExe importImage}'';
          };

          systemd.services.euler-api-txns-refresh = {
            description = "Refresh the Euler API txns staging dev environment";
            after = [ "network-online.target" "incus.service" ];
            wants = [ "network-online.target" ];
            serviceConfig.Type = "oneshot";
            script = ''${lib.getExe refresh}'';
          };

          systemd.timers.euler-api-txns-refresh = {
            description = "Run the Euler API txns staging dev refresh every 2 hours";
            wantedBy = [ "timers.target" ];
            timerConfig = {
              OnCalendar = "*-*-* 00/2:00:00";
              Persistent = true;
              Unit = "euler-api-txns-refresh.service";
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
        { config, inputs, pkgs, lib, ... }:
        let
          inherit (inputs.self.nixosConfigurations.base-container.config.system.build) metadata squashfs;
          apiTxnsFlakeUrl = "git+ssh://git@ssh.bitbucket.juspay.net/jbiz/euler-api-txns.git?ref=staging";

          importImage = pkgs.writeShellApplication {
            name = "incus-import-nixos-container";
            runtimeInputs = [ pkgs.incus ];
            text = ''
              incus image delete base-container 2>/dev/null || true
              echo "Importing container image..."
              incus image import ${metadata}/tarball/nixos-*.tar.xz ${squashfs}/nixos-lxc-image-x86_64-linux.squashfs --alias base-container
              echo "Done. Launch with: incus launch base-container <name>"
            '';
          };

          refresh = pkgs.writeShellApplication {
            name = "euler-api-txns-refresh";
            runtimeInputs = with pkgs; [ git nix openssh ];
            text = ''
              nix develop '${apiTxnsFlakeUrl}' --refresh -c true
              nix build '${apiTxnsFlakeUrl}#automation-test-nix' --no-link --print-out-paths
            '';
          };
        in
        {
          virtualisation.incus.enable = true;

          programs.ssh.extraConfig = ''
            Host ssh.bitbucket.juspay.net
              IdentityFile ${config.clan.core.vars.generators.bitbucket-ssh.files.key.path}
          '';

          systemd.services.incus-import-container = {
            description = "Import initial NixOS container";
            wantedBy = [ "multi-user.target" ];
            after = [ "incus.service" ];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
            };
            script = ''${lib.getExe importImage}'';
          };

          systemd.services.euler-api-txns-refresh = {
            description = "Refresh the Euler API txns staging dev environment";
            after = [ "network-online.target" "incus.service" ];
            wants = [ "network-online.target" ];
            serviceConfig.Type = "oneshot";
            script = ''${lib.getExe refresh}'';
          };

          systemd.timers.euler-api-txns-refresh = {
            description = "Run the Euler API txns staging dev refresh every 2 hours";
            wantedBy = [ "timers.target" ];
            timerConfig = {
              OnCalendar = "*-*-* 00/2:00:00";
              Persistent = true;
              Unit = "euler-api-txns-refresh.service";
            };
          };

          networking.nftables.enable = true;
          networking.firewall.allowedTCPPorts = [ settings.clusterPort ];
          networking.firewall.trustedInterfaces = [ "incusbr0" ];
        };
    };
  };
}

{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
    flake-parts.url = "github:hercules-ci/flake-parts";
    clan-core.url = "git+https://git.clan.lol/clan/clan-core";
    clan-core.inputs.flake-parts.follows = "flake-parts";
    clan-core.inputs.nixpkgs.follows = "nixpkgs";
    # clan-core.inputs.treefmt-nix.follows = ""; # FIXME: infinite recursion
  };
  outputs = inputs@{ self, nixpkgs, disko, flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } ({config, ... }: {
      systems = [ "x86_64-linux" "aarch64-darwin" ];

      imports = [
        inputs.clan-core.flakeModules.default
      ];

      clan = {
        meta.name = "pu";
        meta.domain = "project-unknown";
        meta.description = "Dev containers powered by incus and Nix local-overlay-store";
        specialArgs = { inherit inputs; };

        exportInterfaces.pki = { lib, ... }: {
          options = {
            caUrl        = lib.mkOption { type = lib.types.str; };
            fingerprint  = lib.mkOption { type = lib.types.str; };
            sshUserCAPub = lib.mkOption { type = lib.types.str; };
            provisioner  = lib.mkOption { type = lib.types.str; };
          };
        };

        modules."@juspay/incus"   = ./clanServices/incus;
        modules."@juspay/step-ca" = ./clanServices/step-ca;
        modules."@juspay/pu"      = ./clanServices/pu;

        templates.machine.incus-member = {
          description = "Initialize an Incus cluster member machine";
          path = ./templates/machine/incus-member;
        };

        inventory.machines = {
          idliv2-01.deploy.targetHost = "idliv2-01.tail12b27.ts.net";
          idliv2.deploy.targetHost = "idliv2.tail12b27.ts.net";
          idliv2-02.deploy.targetHost = "idliv2-02.tail12b27.ts.net";
        };

        inventory.instances = {
          incus = {
            module.name = "@juspay/incus";
            module.input = "self";
            roles.bootstrap.machines."idliv2-01" = {
              settings.clusterAddress = "idliv2-01.tail12b27.ts.net";
              settings.clusterPort = 8444;
            };
            roles.member.machines."idliv2" = {
              settings.clusterPort = 8444;
            };
            roles.member.machines."idliv2-02" = {
              settings.clusterPort = 8444;
            };
          };
          step-ca = {
            module.name = "@juspay/step-ca";
            module.input = "self";
            roles.server.machines."idliv2-01" = {
              settings = {
                name        = "pu";
                dns         = [ "idliv2-01.tail12b27.ts.net" "10.10.69.11" "100.123.225.91" ];
                provisioner = "me@shivaraj-bh.in";
              };
            };
          };
          pu = {
            module.name = "@juspay/pu";
            module.input = "self";
            roles.manager.machines."idliv2-01" = {
              settings = {
                instanceManager = "incus";
                certAuthority   = "step-ca";
              };
            };
          };
          sshd = {
            roles.server.tags.all = { };
            roles.server.settings = {
              authorizedKeys = {
                shivaraj-bh = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFN5Ov2zDIG59/DaYKjT0sMWIY15er1DZCT9SIak07vK";
              };
              certificate.enable = false;
            };
          };
          users-root = {
            module.name = "users";
            module.input = "clan-core";
            roles.default.tags.all = { };
            roles.default.settings = {
              user = "root";
              prompt = false;
            };
          };
        };
      };

      flake = {
        nixosConfigurations.base-container = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [ ./containers/base ];
          specialArgs = {
            sshUserCAKeyPub = self.nixosConfigurations."idliv2-01".config.clan.core.vars.generators.step-ca.files.ssh_user_ca_key_pub.path;
          };
        };

        lib.mkPUClientScript =
        let
          stepCAVars = self.nixosConfigurations."idliv2-01".config.clan.core.vars.generators.step-ca.files;
        in
        # TODO: PU_ADMIN is not an appropriate name for the env var
        ''
          PU_HOST="''${PU_HOST:-100.123.225.91}"
          PU_ADMIN="toor"
          export STEP_FINGERPRINT="${builtins.readFile stepCAVars.fingerprint.path}"
          export STEP_CA_URL="https://''${PU_HOST}:8443"
          export STEP_PROVISIONER="me@shivaraj-bh.in"
          export PU_USE_SSH_CA="''${PU_USE_SSH_CA:-true}"
          ${builtins.readFile ./pu/lib/ssh-cert.sh}
          ${builtins.readFile ./pu/pu-client.sh}
        '';
      };

      perSystem = { inputs', pkgs, lib, ... }: {
        formatter = pkgs.nixpkgs-fmt;

        checks = lib.optionalAttrs pkgs.stdenv.isLinux (
          {
            pu-test = pkgs.testers.runNixOSTest (import ./tests { inherit pkgs lib self; });
            incus-storage-benchmark = pkgs.testers.runNixOSTest (import ./tests/incus-storage-benchmark.nix { inherit pkgs lib self; });
            local-overlay-store = pkgs.testers.runNixOSTest (import ./tests/local-overlay-store.nix { inherit pkgs lib self; });
          }
        );

        packages.default = pkgs.writeShellApplication {
          name = "pu";
          runtimeInputs = with pkgs; [ openssh gawk step-cli ];
          text = self.lib.mkPUClientScript;
        };

        apps.incus-cluster-join =
          let
            script = pkgs.writeShellApplication {
              name = "incus-cluster-join";
              runtimeInputs = [ 
                inputs'.clan-core.packages.clan-cli
              ];
              text = 
                let
                  bootstrap = lib.head (lib.attrNames config.flake.clan.inventory.instances.incus.roles.bootstrap.machines);
                  members = lib.attrNames config.flake.clan.inventory.instances.incus.roles.member.machines;
                  clusterPort = 8444; # FIXME: don't hardcode
                in
                lib.concatMapStrings (member:
                  ''
                    echo "Getting join token for ${member} from ${bootstrap}..."
                    token=$(clan ssh ${bootstrap} -c incus cluster add --quiet ${member})

                    echo "Joining cluster on ${member}..."
                    clan ssh ${member} -c incus admin init --preseed <<EOF
                    cluster:
                      enabled: true
                      server_address: ${config.flake.clan.inventory.machines.${member}.deploy.targetHost}:${builtins.toString clusterPort}
                      cluster_token: ''${token}
                    EOF
                    echo "Done. ${member} has joined the cluster."
                  ''
                ) members;
            };
          in
          {
            type = "app";
            program = lib.getExe script;
          };

        apps.incus-import-container =
          let
            container = self.nixosConfigurations.base-container;
            metadata = container.config.system.build.metadata;
            squashfs = container.config.system.build.squashfs;
            script = pkgs.writeShellApplication {
              name = "incus-import-container";
              text = ''
                incus image delete base-container 2>/dev/null || true
                echo "Importing container image..."
                incus image import ${metadata}/tarball/nixos-*.tar.xz ${squashfs}/nixos-lxc-image-x86_64-linux.squashfs --alias base-container
                echo "Done. Launch with: incus launch base-container <name>"
              '';
            };
          in
          lib.optionalAttrs pkgs.stdenv.isLinux {
            type = "app";
            program = lib.getExe script;
          };
        devShells.default = pkgs.mkShell {
          packages = [
            inputs'.clan-core.packages.clan-cli
          ];
        };
      };
    });
}

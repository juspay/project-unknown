{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
    flake-parts.url = "github:hercules-ci/flake-parts";
    agenix.url = "github:ryantm/agenix";
    agenix.inputs.nixpkgs.follows = "nixpkgs";
    agenix.inputs.darwin.follows = "";
    agenix.inputs.home-manager.follows = "";

    clan-core.url = "git+https://git.clan.lol/clan/clan-core";
    clan-core.inputs.flake-parts.follows = "flake-parts";
    clan-core.inputs.nixpkgs.follows = "nixpkgs";
    # clan-core.inputs.treefmt-nix.follows = ""; # FIXME: infinite recursion
  };
  outputs = inputs@{ self, nixpkgs, disko, flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
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

        machines =
          let
            commonModules = [
              inputs.agenix.nixosModules.default
              ({ node, config, ... }: {
                nixpkgs.hostPlatform = "x86_64-linux";
                nix.settings = {
                  max-jobs = "auto";
                  experimental-features = [ "nix-command" "flakes" ];
                  trusted-users = [ "root" ];
                  substituters = [
                    "https://cache.nixos.asia/oss"
                    "https://cache.nixos.asia/juspay"
                  ];
                  trusted-public-keys = [
                    "juspay:5aHaNForWL03wKOGhUn/al4BZd3HqZDWZ3hrVTcf6Fg="
                    "oss:KO872wNJkCDgmGN3xy9dT89WAhvv13EiKncTtHDItVU="
                  ];
                  netrc-file = config.age.secrets."netrc-juspay".path;
                };
                services.tailscale.enable = true;
              })
            ];
          in
          {
            "idliv2-01" = {
              imports = [ ./nodes/idliv2-01 ] ++ commonModules;
              _module.args.node = self.nodes."idliv2-01";
            };
            "idliv2" = {
              imports = [ ./nodes/idliv2 ] ++ commonModules;
              _module.args.node = self.nodes."idliv2";
            };
          };

        inventory.machines = {
          idliv2-01.deploy.targetHost = "idliv2-01.tail12b27.ts.net";
          idliv2.deploy.targetHost = "idliv2.tail12b27.ts.net";
        };

        inventory.instances = {
          incus = {
            module.name = "@juspay/incus";
            module.input = "self";
            roles.standalone.machines."idliv2-01" = { };
            roles.standalone.machines."idliv2" = { };
          };
          step-ca = {
            module.name = "@juspay/step-ca";
            module.input = "self";
            roles.server.machines."idliv2-01" = {
              settings = {
                name        = "pu";
                dns         = [ "idliv2-01.tail12b27.ts.net" ];
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
          admin = {
            roles.default.tags.all = { };
            roles.default.settings.allowedKeys = {
              shivaraj-bh = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFN5Ov2zDIG59/DaYKjT0sMWIY15er1DZCT9SIak07vK";
            };
          };
        };
      };

      flake = {
        # TODO: This needs to go
        nodes = {
          "idliv2-01" = {
            hostName = "idliv2-01";
            useSSHCA = true;
            useHostNixStore = true;
          };
          "idliv2" = {
            hostName = "idliv2";
            useSSHCA = false;
            useHostNixStore = true;
          };
        };

        nixosConfigurations.base-container = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [ ./containers/base ];
          specialArgs = {
            node = self.nodes."idliv2-01";
            sshUserCAKeyPub = self.nixosConfigurations."idliv2-01".config.clan.core.vars.generators.step-ca.files.ssh_user_ca_key_pub.path;
          };
        };

        lib.mkPUClientScript = useSSHCA:
        let
          node = self.nodes."idliv2-01";
          stepCAVars = self.nixosConfigurations."idliv2-01".config.clan.core.vars.generators.step-ca.files;
        in
        # TODO: PU_ADMIN is not an appropriate name for the env var
        ''
          PU_HOST="''${PU_HOST:-${node.hostName}.tail12b27.ts.net}"
          PU_ADMIN="toor"
        '' + (if useSSHCA then ''
          export STEP_FINGERPRINT="${builtins.readFile stepCAVars.fingerprint.path}"
          export STEP_CA_URL="https://''${PU_HOST}:8443"
          export STEP_PROVISIONER="me@shivaraj-bh.in"
          export PU_USE_SSH_CA=true
        '' else ''
          export PU_USE_SSH_CA=false
        '') + ''
          ${builtins.readFile ./pu/lib/ssh-cert.sh}
          ${builtins.readFile ./pu/pu-client.sh}
        '';
      };

      perSystem = { inputs', pkgs, lib, ... }:
      {
        formatter = pkgs.nixpkgs-fmt;

        checks = lib.optionalAttrs pkgs.stdenv.isLinux (
          {
            pu-test = pkgs.testers.runNixOSTest (import ./tests { inherit pkgs lib self; });
            incus-storage-benchmark = pkgs.testers.runNixOSTest (import ./tests/incus-storage-benchmark.nix { inherit pkgs lib self; });
          }
          // lib.optionalAttrs self.nodes."idliv2-01".useHostNixStore {
            local-overlay-store = pkgs.testers.runNixOSTest (import ./tests/local-overlay-store.nix { inherit pkgs lib self; });
          }
        );

        packages.default = pkgs.writeShellApplication {
          name = "pu";
          runtimeInputs = with pkgs; [ openssh gawk ]
            ++ lib.optional self.nodes."idliv2-01".useSSHCA pkgs.step-cli;
          text = self.lib.mkPUClientScript self.nodes."idliv2-01".useSSHCA;
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
    };
}

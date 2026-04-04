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
  };
  outputs = inputs@{ self, nixpkgs, disko, flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" "aarch64-darwin" ];

      flake = {
        node = import ./node.nix;

        nixosConfigurations = {
          ${self.node.hostName} = nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            modules = [
              ./hardware
              ./remote.nix
              ./users.nix
              ./incus.nix
              ./secrets
              inputs.agenix.nixosModules.default
              disko.nixosModules.disko
            ] ++ nixpkgs.lib.optional ((self.node.authMode or "step-ca") == "step-ca") ./step-ca.nix
            ++ [
              ({ node, ... }: {
                nix.settings = {
                  max-jobs = "auto";
                  experimental-features = "nix-command flakes";
                  trusted-users = [ "root" node.admin.name ];
                };
              })
            ];
            specialArgs = {
              node = self.node;
            };
          };

          base-container = nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            modules = [ ./containers/base ];
            specialArgs = {
              node = self.node;
            };
          };
        };
      };

      perSystem = { pkgs, lib, ... }:
      let
        host = "${self.node.hostName}.tail12b27.ts.net";
        authMode = self.node.authMode or "step-ca";
        mkPuClientScript = scriptFile: pkgs.writeShellApplication {
          name = builtins.baseNameOf scriptFile;
          runtimeInputs = with pkgs; [ openssh gawk ]
            ++ lib.optional (authMode == "step-ca") pkgs.step-cli;
          text = ''
            PU_HOST="${host}"
            PU_ADMIN="${self.node.admin.name}"
          '' + (if authMode == "step-ca" then ''
            export STEP_FINGERPRINT="22ab04602f4c98dda666a369ed555863d009a88be8b6f0288c95d7b2dbbe57da"
            export STEP_CA_URL="https://${host}:8443"
            export STEP_PROVISIONER="me@shivaraj-bh.in"
          '' else ''
            PU_AUTH="none"
          '') + ''
            ${builtins.readFile ./pu/lib/auth-client.sh}
            ${builtins.readFile scriptFile}
          '';
        };
      in
      {
        formatter = pkgs.nixpkgs-fmt;

        checks = lib.optionalAttrs pkgs.stdenv.isLinux {
          pu-test = pkgs.testers.runNixOSTest (import ./tests { inherit pkgs lib self; });
          incus-storage-benchmark = pkgs.testers.runNixOSTest (import ./tests/incus-storage-benchmark.nix { inherit pkgs lib self; });
        };

        apps = {
          pu = {
            type = "app";
            program = lib.getExe (mkPuClientScript ./pu/pu-client.sh);
          };
        } // lib.optionalAttrs pkgs.stdenv.isLinux {
          incus-import-container =
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
            {
              type = "app";
              program = lib.getExe script;
            };
        };
      };
    };
}

{
  admin = {
    name = "nix-infra";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFN5Ov2zDIG59/DaYKjT0sMWIY15er1DZCT9SIak07vK" # shivaraj-bh
    ];
  };
  hostName = "idliv2-01";
  sshTarget = "nix-infra@idliv2-01.tail12b27.ts.net";
  incus.bridgeName = "incusbr0";
  authMode = "step-ca"; # "step-ca" | "none"
}

{ config, ... }:
{
  programs.ssh.extraConfig = ''
    Host ssh.bitbucket.juspay.net
      IdentityFile ${config.clan.core.vars.generators.bitbucket-ssh.files.key.path}
  '';

  programs.ssh.knownHosts."ssh.bitbucket.juspay.net" = {
    hostNames = [ "ssh.bitbucket.juspay.net" ];
    publicKey = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC0uTZW1rpND/OC1utyclTge4LV9/qTnM2aefVMdx5Necgj9W06arxU8E8I7Q1rXEU4TGRzfQ7asd41pIMnR1no0gBWKzyI8tmu/4n6W5A3fdL/9V3djNToze6BSd7u1kxy/qSi/q2/vH+67/3yUK7hHkAKKIQeYdKqo2v5WBJkErpxhp1+ZX+ofaw6Sjbk595a4IgPzRFXPyTpHVASMelXbEwbrU7yIS9m0jnUitXMMmgm/m+/nNC1KXCjdGqZimMUKBkDNL1i10Qtvuzh5OIljdE1roSco8NBOhQz77jati2NAhCN9ZeDOxeR1k/mBeMAUTqbPyLhCThrxDvs6nZP";
  };
}

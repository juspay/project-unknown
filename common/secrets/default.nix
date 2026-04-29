{ ... }: {
  clan.core.vars.generators.netrc-juspay = {
    share = true;
    files.netrc = {
      group = "incus-admin";
      mode = "0440";
    };
    prompts.netrc = {
      type = "multiline";
      persist = true;
      description = "netrc file content for Juspay package caches";
    };
  };

  clan.core.vars.generators.bitbucket-ssh = {
    share = true;
    files.key.neededFor = "services";
    script = ''
      # missing trailing newline can sometimes be problematic
      if [ -s "$out/key" ]; then
        tail -c 1 "$out/key" | read -r _ || printf '\n' >> "$out/key"
      fi
    '';
    prompts.key = {
      type = "multiline-hidden";
      persist = true;
    };
  };
}

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
}

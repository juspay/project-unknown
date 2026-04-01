hyp_create() {
  local image="$1" name="$2" owner="$3"
  incus launch --ephemeral --config "user.pu.owner=$owner" -- "$image" "$name" </dev/null >/dev/null 2>&1
}

hyp_destroy() {
  local name="$1"
  incus delete --force -- "$name" >/dev/null 2>&1
}

hyp_list() {
  local owner="$1"
  incus list --format=csv -c n -- "user.pu.owner=$owner" | tr -d ' '
}

hyp_get_owner() {
  local name="$1"
  incus config get -- "$name" user.pu.owner 2>/dev/null || true
}

hyp_get_ip() {
  local name="$1"
  incus list --format csv -c 4 -- "$name" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -1
}

hyp_inject_secrets() {
  local name="$1"
  local netrc="/run/agenix/netrc-juspay"
  if [ -f "$netrc" ]; then
    incus file push --create-dirs --uid 0 --gid 0 --mode 0400 -- "$netrc" "$name/etc/nix/netrc"
  fi
}

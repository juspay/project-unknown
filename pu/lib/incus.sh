inst_create() {
  local image="$1" name="$2" owner="$3"
  incus launch --ephemeral --config "user.pu.owner=$owner" -- "$image" "$name" </dev/null >/dev/null 2>&1
}

inst_destroy() {
  local name="$1"
  incus delete --force -- "$name" >/dev/null 2>&1
}

inst_list() {
  local owner="$1"
  incus list --format=csv -c n -- "user.pu.owner=$owner" 2>/dev/null | tr -d ' '
}

inst_get_owner() {
  local name="$1"
  incus config get -- "$name" user.pu.owner 2>/dev/null
}

inst_get_ip() {
  local name="$1"
  incus list --format csv -c 4 -- "$name" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -1
}

inst_push_file() {
  local name="$1" src="$2" dest="$3" uid="$4" gid="$5" mode="$6"
  incus file push --create-dirs --uid "$uid" --gid "$gid" --mode "$mode" -- "$src" "$name$dest"
}

inst_exists() {
  local name="$1"
  incus info -- "$name" >/dev/null 2>&1
}

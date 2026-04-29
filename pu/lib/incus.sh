PU_STORAGE_POOL="${PU_STORAGE_POOL:-default}"
PU_BASE_IMAGE="${PU_BASE_IMAGE:-base-container}"
PU_HOME_PATH="${PU_HOME_PATH:-/home/toor}"
PU_HOME_DEVICE="${PU_HOME_DEVICE:-pu-home}"
PU_HOME_VOLUME_PREFIX="${PU_HOME_VOLUME_PREFIX:-pu-home-}"

inst_home_volume() {
  echo "${PU_HOME_VOLUME_PREFIX}$1"
}

inst_get_location() {
  local name="$1" location
  location=$(incus query "/1.0/instances/$name" 2>/dev/null | jq -r '.location // ""') || return 1
  [ "$location" = "none" ] && location=""
  echo "$location"
}

inst_home_volume_exists() {
  local name="$1" location="${2:-}"
  local volume target_args=()
  volume=$(inst_home_volume "$name")
  [ -n "$location" ] && target_args=(--target "$location")
  incus storage volume show "${target_args[@]}" -- "$PU_STORAGE_POOL" "$volume" >/dev/null 2>&1
}

inst_delete_home_volume() {
  local name="$1" location="${2:-}"
  local volume target_args=()
  volume=$(inst_home_volume "$name")
  [ -n "$location" ] && target_args=(--target "$location")
  if inst_home_volume_exists "$name" "$location"; then
    incus storage volume delete "${target_args[@]}" -- "$PU_STORAGE_POOL" "$volume" >/dev/null 2>&1 || return 1
  fi
}

inst_attach_home_volume() {
  local name="$1" volume="$2"
  incus storage volume attach -- "$PU_STORAGE_POOL" "$volume" "$name" "$PU_HOME_DEVICE" "$PU_HOME_PATH" >/dev/null 2>&1 || return 1

  for _ in $(seq 1 30); do
    incus exec "$name" -- /run/current-system/sw/bin/chown toor "$PU_HOME_PATH" >/dev/null 2>&1 && return 0
    sleep 1
  done

  return 1
}

inst_launch_rootfs() {
  local image="$1" name="$2" owner="$3"
  incus launch --ephemeral --config "user.pu.owner=$owner" -- "$image" "$name" </dev/null >/dev/null 2>&1
}

inst_cleanup_created() {
  local name="$1" location="${2:-}"
  # Best effort cleanup after a create/fork failure; preserve the original failure.
  incus delete --force -- "$name" >/dev/null 2>&1 || true
  inst_delete_home_volume "$name" "$location" || true
}

inst_create() {
  local image="$1" name="$2" owner="$3"
  local location volume target_args=()

  inst_launch_rootfs "$image" "$name" "$owner" || return 1

  location=$(inst_get_location "$name") || { inst_cleanup_created "$name"; return 1; }
  volume=$(inst_home_volume "$name")
  [ -n "$location" ] && target_args=(--target "$location")

  if ! incus storage volume create "${target_args[@]}" -- "$PU_STORAGE_POOL" "$volume" </dev/null >/dev/null 2>&1; then
    inst_cleanup_created "$name" "$location"
    return 1
  fi

  if ! inst_attach_home_volume "$name" "$volume"; then
    inst_cleanup_created "$name" "$location"
    return 1
  fi
}

inst_destroy() {
  local name="$1"
  local location
  location=$(inst_get_location "$name") || return 1
  incus delete --force -- "$name" >/dev/null 2>&1 || return 1
  inst_delete_home_volume "$name" "$location"
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

inst_ssh_ready() {
  local name="$1"
  incus exec "$name" -- systemctl is-active sshd.socket >/dev/null 2>&1
}

inst_ssh_proxy() {
  local name="$1"
  exec incus exec "$name" -- /run/current-system/sw/bin/socat - TCP4:127.0.0.1:22 2>/dev/null
}

inst_fork() {
  local source="$1" new_name="$2"
  local owner source_location new_location source_volume new_volume copy_args=()

  owner=$(incus config get -- "$source" user.pu.owner 2>/dev/null) || return 1
  source_location=$(inst_get_location "$source") || return 1
  source_volume=$(inst_home_volume "$source")
  new_volume=$(inst_home_volume "$new_name")

  inst_home_volume_exists "$source" "$source_location" || return 1

  inst_launch_rootfs "$PU_BASE_IMAGE" "$new_name" "$owner" || return 1
  new_location=$(inst_get_location "$new_name") || { inst_cleanup_created "$new_name"; return 1; }

  copy_args=(--volume-only)
  [ -n "$new_location" ] && copy_args+=(--destination-target "$new_location")

  if ! incus storage volume copy "${copy_args[@]}" -- "$PU_STORAGE_POOL/$source_volume" "$PU_STORAGE_POOL/$new_volume" </dev/null >/dev/null 2>&1; then
    inst_cleanup_created "$new_name" "$new_location"
    return 1
  fi

  if ! inst_attach_home_volume "$new_name" "$new_volume"; then
    inst_cleanup_created "$new_name" "$new_location"
    return 1
  fi
}

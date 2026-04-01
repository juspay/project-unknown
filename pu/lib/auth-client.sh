client_auth_init() {
  local key_dir="${1:-$PU_STATE_DIR/.pending}"

  if [ "${PU_AUTH:-}" = "none" ]; then
    _pu_ssh_opts=()
    return
  fi

  rm -rf "$key_dir"
  mkdir -p "$key_dir"
  ssh-keygen -t ed25519 -f "$key_dir/key" -N "" -q

  if [ ! -d "$HOME/.step" ]; then
    step ca bootstrap --ca-url "$PU_CA_URL" --fingerprint "$PU_CA_FINGERPRINT"
  fi

  echo "Signing SSH key..." >&2
  step ssh certificate --provisioner "$PU_PROVISIONER" --sign --force me "$key_dir/key.pub"

  _pu_ssh_opts=(-i "$key_dir/key" -o "CertificateFile=$key_dir/key-cert.pub" -o IdentitiesOnly=yes)
}

pu_ssh() {
  # shellcheck disable=SC2029
  ssh "${_pu_ssh_opts[@]}" "pu@${PU_HOST}" "$@"
}

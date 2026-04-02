client_auth_init() {
  _pu_key_dir=$(mktemp -d "$PU_STATE_DIR/.pending-XXXXXX")

  if [ "${PU_AUTH:-}" = "none" ]; then
    _pu_ssh_opts=()
    return
  fi

  ssh-keygen -t ed25519 -f "$_pu_key_dir/key" -N "" -q

  if [ ! -d "$HOME/.step" ]; then
    step ca bootstrap --ca-url "$PU_CA_URL" --fingerprint "$PU_CA_FINGERPRINT"
  fi

  echo "Signing SSH key..." >&2
  step ssh certificate --provisioner "$PU_PROVISIONER" --sign --force me "$_pu_key_dir/key.pub" \
    ${PU_PROVISIONER_PASSWORD_FILE:+--provisioner-password-file "$PU_PROVISIONER_PASSWORD_FILE"}

  _pu_ssh_opts=(-i "$_pu_key_dir/key" -o "CertificateFile=$_pu_key_dir/key-cert.pub" -o IdentitiesOnly=yes)
}

pu_ssh() {
  # shellcheck disable=SC2029
  ssh "${_pu_ssh_opts[@]}" "pu@${PU_HOST}" "$@"
}

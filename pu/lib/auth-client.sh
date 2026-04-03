client_auth_init() {
  if [ "${PU_AUTH:-}" = "none" ]; then
    _pu_ssh_opts=()
    return
  fi

  if [ ! -d "${STEPPATH:-$HOME/.step}" ]; then
    step ca bootstrap
  fi

  if [ ! -f "$PU_STATE_DIR/key-cert.pub" ] || step ssh needs-renewal "$PU_STATE_DIR/key-cert.pub" --expires-in 75% 2>/dev/null; then
    echo "Signing SSH key..." >&2
    step ssh certificate --force --no-agent --no-password --insecure me "$PU_STATE_DIR/key"
  fi

  _pu_ssh_opts=(-i "$PU_STATE_DIR/key" -o "CertificateFile=$PU_STATE_DIR/key-cert.pub" -o IdentitiesOnly=yes)
}

pu_ssh() {
  # shellcheck disable=SC2029
  ssh "${_pu_ssh_opts[@]}" "pu@${PU_HOST}" "$@"
}

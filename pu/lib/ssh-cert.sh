client_auth_init() {
  _pu_instance_ssh_opts=()

  if [ "${PU_USE_SSH_CA:-}" != "true" ]; then
    _pu_ssh_opts=(-o StrictHostKeyChecking=no)
    return
  fi

  if ! step ca health &>/dev/null; then
    step ca bootstrap --force
  fi

  if [ ! -f "$PU_STATE_DIR/key-cert.pub" ] || step ssh needs-renewal "$PU_STATE_DIR/key-cert.pub" --expires-in 75% 2>/dev/null; then
    echo "Signing SSH key..." >&2
    step ssh certificate --force --no-agent --no-password --insecure me "$PU_STATE_DIR/key"
  fi

  _pu_instance_ssh_opts=(-i "$PU_STATE_DIR/key" -o "CertificateFile=$PU_STATE_DIR/key-cert.pub" -o IdentitiesOnly=yes)
  _pu_ssh_opts=(-i "$PU_STATE_DIR/key" -o "CertificateFile=$PU_STATE_DIR/key-cert.pub" -o IdentitiesOnly=yes \
    -o "UserKnownHostsFile=$PU_STATE_DIR/known_hosts" -o StrictHostKeyChecking=accept-new)
}

pu_ssh() {
  # shellcheck disable=SC2029
  ssh -nT "${_pu_ssh_opts[@]}" "pu@${PU_HOST}" "$@"
}

client_auth_init() {
  if [ "${PU_AUTH:-}" = "none" ]; then
    _pu_ssh_opts=()
    return
  fi

  if [ ! -d "$HOME/.step" ]; then
    step ca bootstrap --ca-url "$PU_CA_URL" --fingerprint "$PU_CA_FINGERPRINT"
  fi

  if [ ! -f "$PU_STATE_DIR/key-cert.pub" ] || step ssh needs-renewal "$PU_STATE_DIR/key-cert.pub" --expires-in 75%; then
    echo "Signing SSH key..." >&2
    step ssh certificate --provisioner "$PU_PROVISIONER" --force --no-agent --no-password --insecure me "$PU_STATE_DIR/key" \
      ${PU_PROVISIONER_PASSWORD_FILE:+--provisioner-password-file "$PU_PROVISIONER_PASSWORD_FILE"}
  fi

  _pu_ssh_opts=(-i "$PU_STATE_DIR/key" -o "CertificateFile=$PU_STATE_DIR/key-cert.pub" -o IdentitiesOnly=yes)
}

pu_ssh() {
  # shellcheck disable=SC2029
  ssh "${_pu_ssh_opts[@]}" "pu@${PU_HOST}" "$@"
}

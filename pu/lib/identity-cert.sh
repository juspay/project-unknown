auth_get_identity() {
  if [ -z "${SSH_USER_AUTH:-}" ]; then
    echo "ERR not authenticated with certificate" >&2
    return 1
  fi
  local tmpfile identity
  tmpfile=$(mktemp)
  trap 'rm -f "$tmpfile"' RETURN
  awk '/^publickey/ {print $2, $3}' "$SSH_USER_AUTH" > "$tmpfile"
  identity=$(ssh-keygen -L -f "$tmpfile" 2>/dev/null | awk -F'"' '/Key ID:/ {print $2}') || true
  if [ -z "$identity" ]; then
    echo "ERR could not extract identity from certificate" >&2
    return 1
  fi
  echo "$identity"
}

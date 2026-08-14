#!/bin/zsh
set -eu

export LANG="${LANG:-zh_CN.UTF-8}"
export LC_ALL="${LC_ALL:-zh_CN.UTF-8}"
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BINARY="$SCRIPT_DIR/bin/text-polisher"

for profile in "$HOME/.zprofile" "$HOME/.zshrc"; do
  if [[ -r "$profile" ]]; then
    set +eu
    source "$profile" >/dev/null 2>&1
    set -eu
  fi
done

notify_error() {
  /usr/bin/osascript -e "display notification \"$1\" with title \"文本处理失败\"" >/dev/null 2>&1 || true
}

if [[ ! -x "$BINARY" ]]; then
  if command -v go >/dev/null 2>&1; then
    mkdir -p "$SCRIPT_DIR/bin"
    (cd "$SCRIPT_DIR" && go build -o "$BINARY" ./cmd/text-polisher)
  else
    notify_error "没有找到 Go，也没有可执行文件：$BINARY"
    exit 1
  fi
fi

exec "$BINARY" "$@"

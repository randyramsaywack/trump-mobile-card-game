#!/bin/bash
#
# One-shot deploy of the Linux Server (ARM64) build to the Oracle Cloud VM.
#
# Steps:
#   1. Re-export the trump-server binary via Godot headless mode
#   2. scp it to the VM (preserving execute mode)
#   3. Relabel for SELinux (Oracle Linux blocks exec from user_home_t)
#   4. Restart the systemd service and print status
#
# The Linux Server (ARM64) preset has binary_format/embed_pck=true, so the
# game data is baked into the binary. If embed_pck is ever flipped to false,
# this script needs to also scp build/trump-server.pck and the SELinux step
# stays the same.
#
# Usage:
#   ./deploy-server.sh            # uses defaults below
#   SSH_HOST=other-host ./deploy-server.sh

set -euo pipefail

GODOT_BIN="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"
SSH_HOST="${SSH_HOST:-opc@129.153.37.52}"
REMOTE_DIR="${REMOTE_DIR:-/home/opc/trump}"
SERVICE_NAME="${SERVICE_NAME:-trump-server}"
LOCAL_BIN="build/trump-server"

echo "==> [1/4] Exporting Linux Server (ARM64) binary"
mkdir -p build
"$GODOT_BIN" --headless --export-release "Linux Server (ARM64)" "$LOCAL_BIN"

if [ ! -x "$LOCAL_BIN" ]; then
    echo "ERROR: $LOCAL_BIN missing or not executable after export" >&2
    exit 1
fi

echo "==> [2/4] Copying $LOCAL_BIN to $SSH_HOST:$REMOTE_DIR/$(basename "$LOCAL_BIN")"
scp -p "$LOCAL_BIN" "$SSH_HOST:$REMOTE_DIR/$(basename "$LOCAL_BIN")"

echo "==> [3/4] SELinux relabel + restart on $SSH_HOST"
ssh "$SSH_HOST" "sudo chcon -t bin_t $REMOTE_DIR/$(basename "$LOCAL_BIN") && sudo systemctl restart $SERVICE_NAME"

echo "==> [4/4] Service status"
ssh "$SSH_HOST" "sudo systemctl status $SERVICE_NAME --no-pager"

echo "==> Done. Tail logs with:"
echo "    ssh $SSH_HOST \"sudo journalctl -u $SERVICE_NAME -f\""

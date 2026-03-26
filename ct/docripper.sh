#!/usr/bin/env bash
# Author: godspoon | https://github.com/godspoon
# License: MIT
# DocRipper: https://github.com/godspoon/docripper
# Installer: https://github.com/GodSpoon/DocRipper
#
# Run from your Proxmox HOST shell (not inside a container):
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/GodSpoon/DocRipper/main/ct/docripper.sh)"

# ── Shared UI helpers from community-scripts ──────────────────────────────────
# We source build.func for UI/color/whiptail helpers ONLY.
# We do NOT call build_container() from it (it hardcodes the install URL to
# the community-scripts repo). Instead we create the LXC and run our own
# install script directly.
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)

# ── App metadata ──────────────────────────────────────────────────────────────
APP="DocRipper"
var_tags="${var_tags:-docs;llm}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"

INSTALL_SCRIPT_URL="https://raw.githubusercontent.com/GodSpoon/DocRipper/main/install/docripper-install.sh"

header_info "$APP"
variables
color
catch_errors

# ── Update handler (runs when script is re-run from INSIDE an existing container) ──
function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/docripper ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Stopping ${APP} Service"
  systemctl stop docripper
  msg_ok "Stopped Service"

  msg_info "Pulling Latest ${APP}"
  cd /opt/docripper
  CURRENT_TAG=$(cat .version 2>/dev/null || echo "unknown")
  LATEST_TAG=$(curl -fsSL "https://api.github.com/repos/godspoon/docripper/releases/latest" \
    2>/dev/null | grep '"tag_name"' | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/')

  if [[ -z "$LATEST_TAG" ]]; then
    $STD git pull origin main
  elif [[ "$CURRENT_TAG" == "$LATEST_TAG" ]]; then
    msg_ok "Already on latest version (${LATEST_TAG})"
    systemctl start docripper
    exit
  else
    $STD git fetch --tags
    $STD git checkout "$LATEST_TAG"
    echo "$LATEST_TAG" >.version
  fi
  msg_ok "Pulled ${APP}"

  msg_info "Rebuilding ${APP}"
  $STD npm install
  $STD npm run build
  msg_ok "Rebuilt ${APP}"

  msg_info "Starting ${APP} Service"
  systemctl start docripper
  msg_ok "Started Service"

  msg_ok "Updated successfully!"
  exit
}

# ── Override build_container to use our own install script URL ────────────────
# build.func's build_container() hardcodes the install URL to community-scripts.
# We redefine build_container here — replicating everything it does but pointing
# the final lxc-attach to our own install script.
function build_container() {
  # Build network string
  local NET_STRING="-net0 name=eth0,bridge=${BRG}${MAC},ip=${NET}${GATE}${VLAN}${MTU}"
  case "${IPV6_METHOD:-none}" in
    auto)   NET_STRING+=" ,ip6=auto" ;;
    dhcp)   NET_STRING+=" ,ip6=dhcp" ;;
    static)
      NET_STRING+=",ip6=${IPV6_ADDR:-}"
      [[ -n "${IPV6_GATE:-}" ]] && NET_STRING+=",gw6=${IPV6_GATE}"
      ;;
  esac

  # Features
  local FEATURES="nesting=1"
  [[ "${CT_TYPE}" == "1" ]] && FEATURES="keyctl=1,nesting=1"
  [[ "${ENABLE_FUSE:-no}" == "yes" ]] && FEATURES+=",fuse=1"

  # Export env vars consumed by create_lxc.sh
  export FUNCTIONS_FILE_PATH
  FUNCTIONS_FILE_PATH="$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/install.func)"
  export DIAGNOSTICS RANDOM_UUID
  export CACHER="${APT_CACHER:-}" CACHER_IP="${APT_CACHER_IP:-}"
  export tz="${timezone:-Etc/UTC}"
  export APPLICATION="$APP" app="$NSAPP"
  export PASSWORD="${PW:-}"
  export VERBOSE SSH_ROOT="${SSH:-no}" SSH_AUTHORIZED_KEY="${SSH_AUTHORIZED_KEY:-}"
  export CTID="$CT_ID" CTTYPE="$CT_TYPE"
  export ENABLE_FUSE="${ENABLE_FUSE:-no}" ENABLE_TUN="${ENABLE_TUN:-no}"
  export PCT_OSTYPE="$var_os" PCT_OSVERSION="$var_version"
  export PCT_DISK_SIZE="$DISK_SIZE"
  export PCT_OPTIONS="
    -features ${FEATURES}
    -hostname ${HN}
    -tags ${TAGS}
    ${SD:-} ${NS:-}
    ${NET_STRING}
    -onboot 1
    -cores ${CORE_COUNT}
    -memory ${RAM_SIZE}
    -unprivileged ${CT_TYPE}
    ${PW:-}
  "

  # Create the LXC
  bash -c "$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/create_lxc.sh)" "$?"

  # Start it
  msg_info "Starting LXC Container"
  pct start "$CT_ID"
  local waited=0
  until pct exec "$CT_ID" -- true 2>/dev/null; do
    sleep 2; (( waited+=2 ))
    [[ $waited -ge 60 ]] && { msg_error "Container did not become ready in time"; exit 1; }
  done
  msg_ok "Started LXC Container"

  # Run DocRipper's install script inside the container
  msg_info "Installing ${APP} (this takes a few minutes)"
  lxc-attach -n "$CT_ID" -- bash -c "$(curl -fsSL "${INSTALL_SCRIPT_URL}")"
  msg_ok "Installed ${APP}"
}

# ── Entry point ───────────────────────────────────────────────────────────────
start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:5000${CL}"
echo -e ""
echo -e "${INFO}${YW} To enable AI quality analysis, add your Anthropic API key:${CL}"
echo -e "${TAB}${GN}pct exec ${CT_ID} -- nano /opt/docripper/.env${CL}"
echo -e "${TAB}Uncomment ANTHROPIC_API_KEY, save, then restart the service:"
echo -e "${TAB}${GN}pct exec ${CT_ID} -- systemctl restart docripper${CL}"

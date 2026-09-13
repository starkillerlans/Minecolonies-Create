#!/usr/bin/env bash
#
# sync-mods.sh — pull Minecraft mod jars from a GitHub repo and sync them
# into an AMP instance's mods folder, fixing group ownership/permissions
# so AMP can read them. Designed to run as a regular (non-root) user via
# cron, as long as that user is a member of the AMP group (see setup notes).

set -euo pipefail

# ---------------------------------------------------------------------------
# CONFIG — edit these for your setup
# ---------------------------------------------------------------------------
GIT_REPO_URL="git@github.com:yourname/minecraft-mods.git"   # use https://... if the repo is public
GIT_BRANCH="main"
LOCAL_REPO_DIR="$HOME/mod-repo"              # where this script keeps its own checkout
MODS_SUBDIR="mods"                            # folder inside the repo with the .jar files

AMP_MODS_DIR="/home/amp/.ampdata/instances/InstanceID/Minecraft/mods"  # <-- set to your real instance path
AMP_GROUP="amp"                               # the group AMP's files belong to (check with: ls -l ~amp/.ampdata)

LOG_FILE="$HOME/mod-sync.log"

# Optional: restart the instance automatically after a sync so the new
# mods actually load. Requires the sudoers rule described in the setup
# notes (no root password stored here).
RESTART_AFTER_SYNC=false
AMP_INSTANCE_NAME="InstanceName"              # the AMP instance name, as shown in `ampinstmgr list`
# ---------------------------------------------------------------------------

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG_FILE"; }

# --- Get the latest repo state -------------------------------------------
if [ ! -d "$LOCAL_REPO_DIR/.git" ]; then
    log "No local checkout yet, cloning $GIT_REPO_URL ..."
    git clone --branch "$GIT_BRANCH" "$GIT_REPO_URL" "$LOCAL_REPO_DIR" >> "$LOG_FILE" 2>&1
    CHANGED=true
else
    cd "$LOCAL_REPO_DIR"
    git fetch origin "$GIT_BRANCH" --quiet
    LOCAL_HASH=$(git rev-parse HEAD)
    REMOTE_HASH=$(git rev-parse "origin/$GIT_BRANCH")
    if [ "$LOCAL_HASH" = "$REMOTE_HASH" ]; then
        exit 0   # nothing changed — stay quiet, don't spam the log
    fi
    log "Change detected: $LOCAL_HASH -> $REMOTE_HASH"
    git reset --hard "origin/$GIT_BRANCH" --quiet
    CHANGED=true
fi

# --- Sync into AMP's mods folder and fix permissions ----------------------
if [ "${CHANGED:-false}" = true ]; then
    mkdir -p "$AMP_MODS_DIR"
    rsync -av --delete "$LOCAL_REPO_DIR/$MODS_SUBDIR/" "$AMP_MODS_DIR/" >> "$LOG_FILE" 2>&1

    # chgrp (unlike chown) is allowed for a normal user as long as they are
    # a member of the target group — no root/sudo needed for this part.
    chgrp -R "$AMP_GROUP" "$AMP_MODS_DIR"
    find "$AMP_MODS_DIR" -type d -exec chmod 2775 {} \;
    find "$AMP_MODS_DIR" -type f -exec chmod 664 {} \;

    log "Synced mods into $AMP_MODS_DIR and fixed group/permissions"

    if [ "$RESTART_AFTER_SYNC" = true ]; then
        log "Restarting AMP instance '$AMP_INSTANCE_NAME' ..."
        sudo -u amp ampinstmgr restart "$AMP_INSTANCE_NAME" >> "$LOG_FILE" 2>&1
        log "Restart command sent."
    fi
fi

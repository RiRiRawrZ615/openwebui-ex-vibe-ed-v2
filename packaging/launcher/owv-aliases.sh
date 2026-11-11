#!/usr/bin/env bash
# Shell aliases for a packaged Open Web Vibes install: start, stop, watch, status.
#
# This file is the single source of the alias definitions. The launcher sources it when it is used
# as a library, and /etc/profile.d/openwebvibes.sh sources it for interactive login shells, so a
# fresh install has the same set without anyone editing their shell rc by hand.
#
# Deliberately left out: any alias that could reach a second instance. A packaged install is one
# instance, so there is no dev scope here, and a kill that sweeps by process name or by shared
# port is how a running instance gets taken down by accident. Everything that stops something
# goes through owv-kill.sh, which checks ownership, refuses targets outside its scope, and refuses
# to kill the instance the calling shell is standing inside. --force is the escape hatch, and it
# is the only way to get past that guard.

# v2-scoped, deliberately not OWV_LAUNCHER_DIR. That name belongs to v1, and a machine with both
# packages cannot share it: if it is already set by a shell rc or by v1's profile.d, the ${:-} fallback
# keeps the v1 value and every owv-v2 alias ends up running the v1 launcher. Bind to this file's own
# directory so the alias set always resolves to the package it came from.
OWV_V2_LAUNCHER_DIR="${OWV_V2_LAUNCHER_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

shopt -s expand_aliases

# start
alias launch-owv-v2="bash $OWV_V2_LAUNCHER_DIR/owv.sh"
alias owv-v2="bash $OWV_V2_LAUNCHER_DIR/owv.sh"
alias owv-v2-tmux="tmux new-session -d -s owv-v2 \"bash $OWV_V2_LAUNCHER_DIR/owv.sh\""

# stop
alias kill-owv-v2="bash $OWV_V2_LAUNCHER_DIR/owv-kill.sh"
# A second name for the same thing, because kill-owv can already be defined by the user's shell rc.
# profile.d runs before .bashrc for a login shell and does not run at all for a non-login
# interactive shell, so a packaged definition cannot be relied on to win. Measured on two machines
# where kill-owv still resolved to a stock launcher script. owv-kill is not a name anything else
# defines, so it is unambiguous.
alias owv-v2-kill="bash $OWV_V2_LAUNCHER_DIR/owv-kill.sh"
alias kill-owv-v2-dirty="bash $OWV_V2_LAUNCHER_DIR/owv-kill.sh --force"
alias kill-owv-v2-ui="bash $OWV_V2_LAUNCHER_DIR/owv-kill.sh --ui-only"
alias restart-owv-v2="bash $OWV_V2_LAUNCHER_DIR/owv-kill.sh && bash $OWV_V2_LAUNCHER_DIR/owv.sh"

# look
alias owv-v2-status="bash $OWV_V2_LAUNCHER_DIR/owv-status.sh"

# watch. log-oui renamed to log-owv, and the tails now point at the sinks this launcher actually
# writes. The stock alias named three files and this launcher only ever fed one of them, so two
# thirds of it showed stale content from days ago.
alias log-owv='state="${XDG_STATE_HOME:-$HOME/.local/state}/openwebvibes-v2"; tail -F "$HOME/Documents/openwebui.log" "$HOME/Documents/engine.log" "$HOME/Documents/llama.log" "$state/openwebvibes.log" "$state/backend.log" 2>/dev/null'
alias tail-eng='state="${XDG_STATE_HOME:-$HOME/.local/state}/openwebvibes-v2"; tail -F "$HOME/Documents/engine.log" "$HOME/Documents/llama.log" "$state/backend.log" "$state/open-terminal.log" 2>/dev/null'
alias tail-owv='state="${XDG_STATE_HOME:-$HOME/.local/state}/openwebvibes-v2"; tail -F "$state/openwebvibes.log" "$state/backend.log" "$state/open-terminal.log" 2>/dev/null'

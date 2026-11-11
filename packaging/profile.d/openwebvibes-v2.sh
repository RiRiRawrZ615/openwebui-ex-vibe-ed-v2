# Interactive shells only. Aliases do not expand in a non-interactive shell, so sourcing this from
# a script would define them and then fail to use them.
#
# v2 is a separate package, so this file is separate too. It sources the v2 alias set, which uses
# v2 names (owv-v2, kill-owv-v2). A machine with both packages gets both sets without either file
# overwriting the other, and no alias from one package can stop the other instance.
if [[ -n "$BASH_VERSION" && $- == *i* ]]; then
    OWV_V2_LAUNCHER_DIR="${OWV_V2_LAUNCHER_DIR:-/usr/lib/openwebvibes-v2/launcher}"
    if [[ -f "$OWV_V2_LAUNCHER_DIR/owv-aliases.sh" ]]; then
        source "$OWV_V2_LAUNCHER_DIR/owv-aliases.sh"
    fi
fi

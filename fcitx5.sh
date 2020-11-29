#!/bin/sh

export FCITX_ADDON_DIRS=/app/lib/fcitx5
for dir in `ls /app/addons/`; do
    export FCITX_ADDON_DIRS=/app/addons/$dir/lib/fcitx5:$FCITX_ADDON_DIRS
    export XDG_DATA_DIRS=/app/addons/$dir/share:${XDG_DATA_DIRS}
    export PATH=/app/addons/$dir/bin:$PATH
done

exec fcitx5-bin "$@"

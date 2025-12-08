#!/bin/sh

export GI_TYPELIB_PATH=$GI_TYPELIB_PATH:/app/addons/Keyman/lib/x86_64-linux-gnu/girepository-1.0/
export PYTHONPATH=/app/addons/Keyman/lib/python3.13/site-packages/

exec /app/addons/Keyman/bin/km-config.real

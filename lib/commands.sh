# shellcheck shell=bash

# ------------------------------
# 命令装配层
# 对外保留单一入口，内部再拆分模块
# ------------------------------

. "${SCRIPT_ROOT}/lib/change.sh"
. "${SCRIPT_ROOT}/lib/cli.sh"

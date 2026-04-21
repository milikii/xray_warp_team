#!/usr/bin/env bash

set -Eeuo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/cases_output.sh"
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/cases_state_and_change.sh"
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/cases_cli_and_install.sh"

main() {
  load_functions
  stub_side_effects
  run_warp_enabled_case
  run_warp_disabled_case
  run_output_helper_case
  run_xray_config_escape_case
  run_generated_file_atomic_failure_case
  run_state_context_case
  run_usage_case
  run_install_self_command_case
  run_install_validation_case
  run_xray_digest_parse_case
  run_install_xray_checksum_failure_case
  run_service_config_helper_case
  run_managed_apply_case
  run_managed_rollback_case
  run_install_rollback_helper_case
  run_tls_stage_failure_case
  run_warp_xml_escape_case
  run_change_helper_case
  run_install_parse_case
  run_cert_mode_input_case
  run_change_command_case
  run_upgrade_command_case
  run_missing_option_value_case
  run_dispatch_case
  run_install_flow_case
  printf 'smoke ok\n'
}

main "$@"

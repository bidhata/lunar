# full_audit_startup_services
#
# Audit startup services
#.

full_audit_startup_services () {
  audit_xinetd
  audit_chkconfig
  audit_legacy
  audit_inetd
  audit_inetd_logging
}
#!/bin/bash

set -e 
export LC_ALL=C

days_of_backups="5"
backup_owner="backup"
parent_dir="/backups/mysql"
defaults_file="/etc/mysql/backup.cnf"
now="$(date +%Y-%m-%d_%H-%M-%S)"
today="$(date +%Y-%m-%d)"
todays_dir="${parent_dir}/${today}"
#encryption_key_file="${parent_dir}/encryption_key"
log_file="${todays_dir}/backup-progress.log"
processors="$(nproc --all)"


error () {
  printf "%s: %s\n" "$(basename "${BASH_SOURCE}")" "${1}" >&2
  exit 1
}

trap 'error "An unexpected error occurred."' ERR


sanity_check () {
  if [ "$USER" != "$backup_owner" ]; then
    error "Script can only be run as the \"$backup_owner\" user"
  fi
}


set_options () {
  backup_args=(
    "--defaults-file=${defaults_file}"
    "--extra-lsndir=${todays_dir}"
    "--backup"
    "--stream=xbstream"
    "--parallel=${processors}"
  )
  backup_type="full"

  # Add option to read LSN (log sequence number) if a full backup has been
  # taken today.
  if grep -q -s "to_lsn" "${todays_dir}/xtrabackup_checkpoints"; then
    backup_type="incremental"
    lsn=$(awk '/to_lsn/ {print $3;}' "${todays_dir}/xtrabackup_checkpoints")
    backup_args+=( "--incremental-lsn=${lsn}" )
  fi
}


rotate_old () {
  day_dir_to_remove="${parent_dir}/$(date --date="${days_of_backups} days ago" +%Y-%m-%d)"

  if [ -d "${day_dir_to_remove}" ]; then
    rm -rf "${day_dir_to_remove}"
  fi
}


take_backup () {
  mkdir -p "${todays_dir}"
  find "${todays_dir}" -type f -name "*.incomplete" -delete
  mariabackup "${backup_args[@]}" "--target-dir=${todays_dir}" > "${todays_dir}/${backup_type}-${now}.xbstream.incomplete" 2> "${log_file}"
  mv "${todays_dir}/${backup_type}-${now}.xbstream.incomplete" "${todays_dir}/${backup_type}-${now}.xbstream"
}


sanity_check && set_options && rotate_old && take_backup


# Check success and print message
if tail -1 "${log_file}" | grep -q "completed OK"; then
  printf "Backup successful!\n"
  printf "Backup created at %s/%s-%s.xbstream\n" "${todays_dir}" "${backup_type}" "${now}"
else
  error "Backup failure! Check ${log_file} for more information"
fi



#!/bin/bash
# Script to update the parameters passed to container image

: ${HOST_DEV_DIR:=/mnt/host-dev}
: ${CGROUP_PIDS_MAX:=max}
: ${TCMU_LOCKDIR:=/var/run/lock}

set_cgroup_pids() {
  local ret=0
  local pids=$1
  local cgroup max

  cgroup=$(awk -F: '/:pids:/{print $3}' /proc/self/cgroup)

  max=$(cat /sys/fs/cgroup/pids/"${cgroup}"/pids.max)
  echo "maximum number of pids configured in cgroups: ${max}"

  echo "${pids}" > /sys/fs/cgroup/pids/"${cgroup}"/pids.max
  ret=$?

  max=$(cat /sys/fs/cgroup/pids/"${cgroup}"/pids.max)
  echo "maximum number of pids configured in cgroups (reconfigured): ${max}"

  return ${ret}
}

# do not change cgroup/pids when CGROUP_PIDS_MAX is set to 0
if [[ "${CGROUP_PIDS_MAX}" != '0' ]]
then
  set_cgroup_pids ${CGROUP_PIDS_MAX}
fi

if [ -c "${HOST_DEV_DIR}/zero" ] && [ -c "${HOST_DEV_DIR}/null" ]; then
    # looks like an alternate "host dev" has been provided
    # to the container. Use that as our /dev ongoing
    mount --rbind "${HOST_DEV_DIR}" /dev
fi

# Hand off to CMD
exec "$@"

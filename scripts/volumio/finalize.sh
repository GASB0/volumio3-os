#!/bin/bash

set -eo pipefail

function check_size() {
  local path=$1
  if [[ -e "${path}" ]]; then
    du -sh0 "${path}" 2>/dev/null | cut -f1
  else
    echo ""
  fi
}

[ -z "${ROOTFSMNT}" ] && ROOTFSMNT=/mnt/volumio/rootfs
echo "Computing Volumio folder Hash Checksum" "info"

HASH="$(md5deep -r -l -s -q ${ROOTFSMNT}/volumio | sort | md5sum | awk '{print $1}')"
echo "HASH: ${HASH}" "dbg"
cat <<-EOF >>${ROOTFSMNT}/etc/os-release
VOLUMIO_HASH="${HASH}"
EOF
# base-files updates can overwrite our custom info.
echo "Checking os-release"
if ! grep "VOLUMIO_HARDWARE" ${ROOTFSMNT}/etc/os-release; then
  echo "Missing VOLUMIO_ info in /etc/os-release!" "err"
  cat ${ROOTFSMNT}/etc/os-release
  exit 10 # Bail!
fi
echo "Cleaning rootfs to save space" "info"
# Remove our apt cache proxy
[[ -e "${ROOTFSMNT}/etc/apt/apt.conf.d/02cache" ]] && rm "${ROOTFSMNT}/etc/apt/apt.conf.d/02cache"

echo "Cleaning docs"
echo "Pre /usr/share/" "$(check_size /usr/share)"
share_dirs=("doc" "locale" "man")
declare -A pre_size
for path in "${share_dirs[@]}"; do
  pre_size["${path}"]=$(check_size "/usr/share/${path}")
done

find ${ROOTFSMNT}/usr/share/doc -depth -type f ! -name copyright -delete # Remove docs that aren't copyrights
find ${ROOTFSMNT}/usr/share/doc -empty -delete                           # Empty files
find ${ROOTFSMNT}/usr/share/doc -type l -delete                          # Remove missing symlinks

# if [[ ${BUILD:0:3} == arm ]]; then
echo "Cleaning man and caches"
rm -rf ${ROOTFSMNT}/usr/share/man/* ${ROOTFSMNT}/usr/share/groff/* ${ROOTFSMNT}/usr/share/info/*
rm -rf ${ROOTFSMNT}/usr/share/lintian/* ${ROOTFSMNT}/usr/share/linda/* ${ROOTFSMNT}/var/cache/man/*

rm -rf ${ROOTFSMNT}/var/lib/apt/lists/*
rm -rf ${ROOTFSMNT}/var/cache/apt/*

echo "Final /usr/share/" "$(check_size /usr/share)"
for path in "${share_dirs[@]}"; do
  echo "${path}:" "Pre: ${pre_size[$path]} Post: $(check_size "/usr/share/${path}")"
done

#TODO: This doesn't seem to be doing much atm
echo "Stripping binaries"
STRP_DIRECTORIES=("${ROOTFSMNT}/lib/"
  "${ROOTFSMNT}/bin/"
  "${ROOTFSMNT}/usr/sbin"
  "${ROOTFSMNT}/usr/local/bin/"
  "${ROOTFSMNT}/lib/modules/")

for DIR in "${STRP_DIRECTORIES[@]}"; do
  echo "$DIR Pre  size" "$(check_size "$DIR")"
  find "$DIR" -type f -exec strip --strip-unneeded {} ';' >/dev/null 2>&1
  echo "$DIR Post size" "$(check_size "$DIR")"
done
# else
#   echo "${BUILD} environment detected, not cleaning/stripping libs"
# fi

echo "Checking rootfs size"
echo "Rootfs:" "$(check_size ${ROOTFSMNT})"
echo "Volumio parts:" "$(check_size ${ROOTFSMNT}/volumio) $(check_size ${ROOTFSMNT}/myvolumio)"

# Got to do this here to make it stick
echo "Updating MOTD"
rm -f ${ROOTFSMNT}/etc/motd ${ROOTFSMNT}/etc/update-motd.d/*
cp "${SRC}"/volumio/etc/update-motd.d/* ${ROOTFSMNT}/etc/update-motd.d/

#TODO This shall be refactored as per https://github.com/volumio/Build/issues/479
# Temporary workaround
echo "Copying over upmpdcli.service"
cp ${SRC}/volumio/lib/systemd/system/upmpdcli.service ${ROOTFSMNT}/lib/systemd/system/upmpdcli.service

echo "Copying over shairport-sync.service"
[ -e "${ROOTFSMNT}/lib/systemd/system/shairport-sync.service" ] && rm ${ROOTFSMNT}/lib/systemd/system/shairport-sync.service
cp ${SRC}/volumio/lib/systemd/system/shairport-sync.service ${ROOTFSMNT}/lib/systemd/system/shairport-sync.service

echo "Add Volumio WebUI IP"
cat <<-EOF >>${ROOTFSMNT}/etc/issue
Welcome to Volumio!
WebUI available at \n.local (\4)
EOF

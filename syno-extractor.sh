#!/usr/bin/env bash

ROOT_PATH=$PWD/files
TOOL_PATH="$(dirname $(readlink -f "$0"))/syno-extractor"

GITHUB_URL="https://raw.githubusercontent.com/wjz304/Redpill_CustomBuild/main/syno-extractor"
#GITHUB_URL="https://fastly.jsdelivr.net/gh/wjz304/Redpill_CustomBuild@main/syno-extractor"
[ ! -d "${TOOL_PATH}" ] && mkdir -p "${TOOL_PATH}"
for f in libcurl.so.4 libmbedcrypto.so.5 libmbedtls.so.13 libmbedx509.so.1 libmsgpackc.so.2 libsodium.so libsynocodesign-ng-virtual-junior-wins.so.7 syno_extract_system_patch; do
  [ ! -e "${TOOL_PATH}/${f}" ] && curl -skL "${GITHUB_URL}/${f}" -o "${TOOL_PATH}/${f}"
done
chmod -R +x "${TOOL_PATH}"
LD_LIBRARY_PATH="${TOOL_PATH}" "${TOOL_PATH}/syno_extract_system_patch" $@


# GET
#
# #!/usr/bin/env bash
# 
# TOOL_PATH="$(dirname $(readlink -f "$0"))/syno-extractor"
# CACHE_DIR="${TOOL_PATH}/cache"
# 
# [ -d "${CACHE_DIR}" ] && rm -rf "${CACHE_DIR}"
# mkdir -p "${CACHE_DIR}"
# 
# OLDPAT_URL="https://cndl.synology.cn/download/DSM/release/7.0.1/42218/DSM_DS3622xs%2B_42218.pat"
# #OLDPAT_URL="https://global.download.synology.com/download/DSM/release/7.0.1/42218/DSM_DS3622xs%2B_42218.pat"
# OLDPAT_FILE="DSM_DS3622xs+_42218.pat"
# STATUS=`curl -# -w "%{http_code}" -L "${OLDPAT_URL}" -o "${CACHE_DIR}/${OLDPAT_FILE}"`
# if [ $? -ne 0 -o ${STATUS} -ne 200 ]; then
#   echo "[E] DSM_DS3622xs%2B_42218.pat download error!"
#   rm -rf ${CACHE_DIR}
#   exit 1
# fi
# 
# mkdir "${CACHE_DIR}/ramdisk"
# tar -C "${CACHE_DIR}/ramdisk/" -xf "${CACHE_DIR}/${OLDPAT_FILE}" rd.gz 2>&1
# if [ $? -ne 0 ]; then
#   echo "[E] extractor rd.gz error!"
#   rm -rf ${CACHE_DIR}
#   exit 1
# fi
# (cd "${CACHE_DIR}/ramdisk"; xz -dc < rd.gz | cpio -idm) >/dev/null 2>&1 || true
# 
# # Copy only necessary files
# for f in libcurl.so.4 libmbedcrypto.so.5 libmbedtls.so.13 libmbedx509.so.1 libmsgpackc.so.2 libsodium.so libsynocodesign-ng-virtual-junior-wins.so.7; do
#   cp "${CACHE_DIR}/ramdisk/usr/lib/${f}" "${TOOL_PATH}"
# done
# cp "${CACHE_DIR}/ramdisk/usr/syno/bin/scemd" "${TOOL_PATH}/syno_extract_system_patch"
# rm -rf ${CACHE_DIR}
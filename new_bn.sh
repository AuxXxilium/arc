#!/usr/bin/env bash

set -e

MODEL_CONFIG_PATH="./files/board/arpl/overlayfs/opt/arpl/model-configs"
CONSTS_FILE="./files/board/arpl/overlayfs/opt/arpl/include/consts.sh"
# Waiting for Userinput - Buildnumber
read -p "Buildnumber (eq: 42962): " BUILDNUMBER
# Grep List of Model Configs
SYSLIST=$(ls ${MODEL_CONFIG_PATH} | sed G | sed 's/.yml//g')
# Grep Latest Build from Consts
LAST_BUILDNUMBER=$(sed -n 's/^BUILDNUMBER=\(.*\)/\1/p' < ${CONSTS_FILE} | sed 's!"!!g')
EXTRA=""

# Add functions to get script working
function readConfigKey() {
  RESULT=`yq eval '.'${1}' | explode(.)' "${2}"`
  [ "${RESULT}" == "null" ] && echo "" || echo ${RESULT}
}
function readModelKey() {
  readConfigKey "${2}" "${MODEL_CONFIG_PATH}/${1}.yml"
}
function writeConfigKey() {
  [ "${2}" = "{}" ] && yq eval '.'${1}' = {}' --inplace "${3}" || \
    yq eval '.'${1}' = "'${2}'"' --inplace "${3}"
}

# Update with same Buildnumber
if [ "${BUILDNUMBER}" == "${LAST_BUILDNUMBER}" ]; then
for MODEL in ${SYSLIST} ; do
  # Read Data from Config
  RELEASE="`readModelKey "${MODEL}" "builds.${BUILDNUMBER}.ver"`"
  KVERS="`readModelKey "${MODEL}" "builds.${BUILDNUMBER}.kver"`"
  # Make new Hash
  MODEL_CODED=$(echo ${MODEL} | sed 's/+/%2B/g')
  URL="https://global.download.synology.com/download/DSM/release/${RELEASE}/${BUILDNUMBER}${EXTRA}/DSM_${MODEL_CODED}_${BUILDNUMBER}.pat"
  #URL="https://archive.synology.com/download/Os/DSM/${RELEASE}-${BUILDNUMBER}/DSM_${MODEL_CODED}_${BUILDNUMBER}.pat"
  FILENAME="${MODEL}-${BUILDNUMBER}.pat"
  FILEPATH="/tmp/${FILENAME}"
  echo -n "Checking ${MODEL}... "
  if [ -f ${FILEPATH} ]; then
    echo "cached"
  else
    echo "not cached, downloading..."
  fi
  STATUS=`curl --progress-bar -o ${FILEPATH} -w "%{http_code}" -L "${URL}"`
  if [ ${STATUS} -ne 200 ]; then
    echo "error: HTTP status = ${STATUS}"
    rm -f ${FILEPATH}
    continue
  fi
  echo "Calculating md5:"
  PAT_MD5=`md5sum ${FILEPATH} | awk '{print$1}'`
  echo "Calculating sha256:"
  sudo rm -rf /tmp/extracted
  ./syno-extractor.sh "/tmp/${FILENAME}" "/tmp/extracted"
  PAT_CS=`sha256sum ${FILEPATH} | awk '{print$1}'`
  ZIMAGE_CS=`sha256sum /tmp/extracted/zImage | awk '{print$1}'`
  RD_CS=`sha256sum /tmp/extracted/rd.gz | awk '{print$1}'`
  sudo rm -rf /tmp/extracted
  # Export new Hash to Config
  writeConfigKey "builds.${BUILDNUMBER}.pat.url" "${URL}" "${MODEL_CONFIG_PATH}/${MODEL}.yml"
  writeConfigKey "builds.${BUILDNUMBER}.pat.hash" "${PAT_CS}" "${MODEL_CONFIG_PATH}/${MODEL}.yml"
  writeConfigKey "builds.${BUILDNUMBER}.pat.ramdisk-hash" "${RD_CS}" "${MODEL_CONFIG_PATH}/${MODEL}.yml"
  writeConfigKey "builds.${BUILDNUMBER}.pat.zimage-hash" "${ZIMAGE_CS}" "${MODEL_CONFIG_PATH}/${MODEL}.yml"
  writeConfigKey "builds.${BUILDNUMBER}.pat.md5-hash" "${PAT_MD5}" "${MODEL_CONFIG_PATH}/${MODEL}.yml"
  # Show Message to User
  echo "${MODEL}/${BUILDNUMBER} updated in Config"
done
fi

# Add a new Buildnumber
if [ "${BUILDNUMBER}" != "${LAST_BUILDNUMBER}" ]; then
  read -p "Release (eq: 7.1.1): " RELEASE
  read -p "Beta (y/n): " BETA
for MODEL in ${SYSLIST} ; do
  # Wait for Userinput - Release and Kernelversion
  echo "Model: ${MODEL}"
  read -p "Kernel (eq: 4.4.180): " KVERS
  # Get DT from Config
  DT="`readModelKey "${MODEL}" "dt"`"
  # Make new Hash
  MODEL_CODED=$(echo ${MODEL} | sed 's/+/%2B/g')
  if [ "${BETA}" = "n" ]; then
  URL="https://global.download.synology.com/download/DSM/release/${RELEASE}/${BUILDNUMBER}${EXTRA}/DSM_${MODEL_CODED}_${BUILDNUMBER}.pat"
  elif [ "${BETA}" = "y" ]; then
  URL="https://global.download.synology.com/download/DSM/beta/${RELEASE}/${BUILDNUMBER}${EXTRA}/DSM_${MODEL_CODED}_${BUILDNUMBER}.pat"
  fi
  FILENAME="${MODEL}-${BUILDNUMBER}.pat"
  FILEPATH="/tmp/${FILENAME}"
  echo -n "Checking ${MODEL}... "
  if [ -f ${FILEPATH} ]; then
    echo "cached"
  else
    echo "not cached, downloading..."
  fi
  STATUS=`curl --progress-bar -o ${FILEPATH} -w "%{http_code}" -L "${URL}"`
  if [ ${STATUS} -ne 200 ]; then
    echo "error: HTTP status = ${STATUS}"
    rm -f ${FILEPATH}
    continue
  fi
  echo "Calculating md5:"
  PAT_MD5=`md5sum ${FILEPATH} | awk '{print$1}'`
  echo "Calculating sha256:"
  sudo rm -rf /tmp/extracted
  ./syno-extractor.sh "/tmp/${FILENAME}" "/tmp/extracted"
  PAT_CS=`sha256sum ${FILEPATH} | awk '{print$1}'`
  ZIMAGE_CS=`sha256sum /tmp/extracted/zImage | awk '{print$1}'`
  RD_CS=`sha256sum /tmp/extracted/rd.gz | awk '{print$1}'`
  sudo rm -rf /tmp/extracted
  # Export new Build to Config
  echo "\n" >> ${MODEL_CONFIG_PATH}/${MODEL}.yml
  echo "  ${BUILDNUMBER}:" >> ${MODEL_CONFIG_PATH}/${MODEL}.yml
  echo "    ver: "${RELEASE}"" >> ${MODEL_CONFIG_PATH}/${MODEL}.yml
  echo "    kver: "${KVERS}"" >> ${MODEL_CONFIG_PATH}/${MODEL}.yml
  echo "    rd-compressed: false" >> ${MODEL_CONFIG_PATH}/${MODEL}.yml
  echo "    cmdline:" >> ${MODEL_CONFIG_PATH}/${MODEL}.yml
  echo "      <<: *cmdline" >> ${MODEL_CONFIG_PATH}/${MODEL}.yml
  echo "    synoinfo:" >> ${MODEL_CONFIG_PATH}/${MODEL}.yml
  echo "      <<: *synoinfo" >> ${MODEL_CONFIG_PATH}/${MODEL}.yml
  echo "    pat:" >> ${MODEL_CONFIG_PATH}/${MODEL}.yml
  echo "      url: "${URL}"" >> ${MODEL_CONFIG_PATH}/${MODEL}.yml
  echo "      hash: "${PAT_CS}"" >> ${MODEL_CONFIG_PATH}/${MODEL}.yml
  echo "      ramdisk-hash: "${RD_CS}"" >> ${MODEL_CONFIG_PATH}/${MODEL}.yml
  echo "      zimage-hash: "${ZIMAGE_CS}"" >> ${MODEL_CONFIG_PATH}/${MODEL}.yml
  echo "      md5-hash: "${PAT_MD5}"" >> ${MODEL_CONFIG_PATH}/${MODEL}.yml
  echo "    patch:" >> ${MODEL_CONFIG_PATH}/${MODEL}.yml
  echo "      - "ramdisk-common-disable-root-pwd.patch"" >> ${MODEL_CONFIG_PATH}/${MODEL}.yml
  echo "      - "ramdisk-common-init-script.patch"" >> ${MODEL_CONFIG_PATH}/${MODEL}.yml
  echo "      - "ramdisk-common-etc-rc.patch"" >> ${MODEL_CONFIG_PATH}/${MODEL}.yml
  echo "      - "ramdisk-42951-post-init-script.patch"" >> ${MODEL_CONFIG_PATH}/${MODEL}.yml
  if [ ${DT} = "false" ]; then
  echo "      - "ramdisk-42661-disable-disabled-ports.patch"" >> ${MODEL_CONFIG_PATH}/${MODEL}.yml
  fi
  # Write new Buildnumber to Consts
  sed -i 's/BUILDNUMBER=\s.*$/BUILDNUMBER="${BUILDNUMBER}"/' ${CONSTS_FILE}
  # Show Message to User
  echo "${MODEL}/${BUILDNUMBER} added to Config"
done
fi
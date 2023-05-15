###############################################################################
# Shows update menu to user
function updateMenu() {
  NEXT="1"
  CONFDONE="`readConfigKey "arc.confdone" "${USER_CONFIG_FILE}"`"
  if [ -n "${CONFDONE}" ]; then
    PLATFORM="`readModelKey "${MODEL}" "platform"`"
    KVER="`readModelKey "${MODEL}" "builds.${BUILD}.kver"`"
    while true; do
      dialog --backtitle "`backtitle`" --menu "Choose an Option" 0 0 0 \
        1 "Full upgrade Loader" \
        2 "Update Arc Loader" \
        3 "Update Addons" \
        4 "Update LKMs" \
        5 "Update Modules" \
        0 "Exit" \
        2>${TMP_PATH}/resp
      [ $? -ne 0 ] && return
      case "`<${TMP_PATH}/resp`" in
        1)
          dialog --backtitle "`backtitle`" --title "Full upgrade Loader" --aspect 18 \
            --infobox "Checking latest version" 0 0
          ACTUALVERSION="v${ARPL_VERSION}"
          TAG="`curl --insecure -s https://api.github.com/repos/AuxXxilium/arc/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3)}'`"
          if [ $? -ne 0 -o -z "${TAG}" ]; then
            dialog --backtitle "`backtitle`" --title "Full upgrade Loader" --aspect 18 \
              --msgbox "Error checking new version" 0 0
            continue
          fi
          if [ "${ACTUALVERSION}" = "${TAG}" ]; then
            dialog --backtitle "`backtitle`" --title "Full upgrade Loader" --aspect 18 \
              --yesno "No new version. Actual version is ${ACTUALVERSION}\nForce update?" 0 0
            [ $? -ne 0 ] && continue
          fi
          dialog --backtitle "`backtitle`" --title "Full upgrade Loader" --aspect 18 \
            --infobox "Downloading latest version ${TAG}" 0 0
          # Download update file
          STATUS=`curl --insecure -w "%{http_code}" -L \
            "https://github.com/AuxXxilium/arc/releases/download/${TAG}/arc-${TAG}.img.zip" -o /tmp/arc-${TAG}.img.zip`
          if [ $? -ne 0 -o ${STATUS} -ne 200 ]; then
            dialog --backtitle "`backtitle`" --title "Full upgrade Loader" --aspect 18 \
              --msgbox "Error downloading update file" 0 0
            continue
          fi
          unzip -o /tmp/arc-${TAG}.img.zip -d /tmp
          if [ $? -ne 0 ]; then
            dialog --backtitle "`backtitle`" --title "Full upgrade Loader" --aspect 18 \
              --msgbox "Error extracting update file" 0 0
            continue
          fi
          if [ -f "${USER_CONFIG_FILE}" ]; then
            GENHASH=`cat /mnt/p1/user-config.yml | curl -s -F "content=<-" http://dpaste.com/api/v2/ | cut -c 19-`
            dialog --backtitle "`backtitle`" --title "Full upgrade Loader" --aspect 18 \
            --msgbox "Backup config successfull!\nWrite down your Code: ${GENHASH}\n\nAfter Reboot use: Backup - Restore with Code." 0 0
          else
            dialog --backtitle "`backtitle`" --title "Full upgrade Loader" --aspect 18 \
            --infobox "No config for Backup found!" 0 0
          fi
          dialog --backtitle "`backtitle`" --title "Full upgrade Loader" --aspect 18 \
            --infobox "Installing new Image" 0 0
          # Process complete update
          umount /mnt/p1 /mnt/p2 /mnt/p3
          dd if="/tmp/arc.img" of=`blkid | grep 'LABEL="ARPL3"' | cut -d3 -f1` bs=1M conv=fsync
          # Ask for Boot
          dialog --backtitle "`backtitle`" --title "Full upgrade Loader" --aspect 18 \
            --yesno "Arc updated with success to ${TAG}!\nReboot?" 0 0
          [ $? -ne 0 ] && continue
          arpl-reboot.sh config
          exit
          ;;
        2)
          dialog --backtitle "`backtitle`" --title "Update Arc" --aspect 18 \
            --infobox "Checking latest version" 0 0
          ACTUALVERSION="v${ARPL_VERSION}"
          TAG="`curl --insecure -s https://api.github.com/repos/AuxXxilium/arc/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3)}'`"
          if [ $? -ne 0 -o -z "${TAG}" ]; then
            dialog --backtitle "`backtitle`" --title "Update Arc" --aspect 18 \
              --msgbox "Error checking new version" 0 0
            continue
          fi
          if [ "${ACTUALVERSION}" = "${TAG}" ]; then
            dialog --backtitle "`backtitle`" --title "Update Arc" --aspect 18 \
              --yesno "No new version. Actual version is ${ACTUALVERSION}\nForce update?" 0 0
            [ $? -ne 0 ] && continue
          fi
          dialog --backtitle "`backtitle`" --title "Update Arc" --aspect 18 \
            --infobox "Downloading latest version ${TAG}" 0 0
          # Download update file
          STATUS=`curl --insecure -w "%{http_code}" -L \
            "https://github.com/AuxXxilium/arc/releases/download/${TAG}/update.zip" -o /tmp/update.zip`
          if [ $? -ne 0 -o ${STATUS} -ne 200 ]; then
            dialog --backtitle "`backtitle`" --title "Update Arc" --aspect 18 \
              --msgbox "Error downloading update file" 0 0
            continue
          fi
          unzip -oq /tmp/update.zip -d /tmp
          if [ $? -ne 0 ]; then
            dialog --backtitle "`backtitle`" --title "Update Arc" --aspect 18 \
              --msgbox "Error extracting update file" 0 0
            continue
          fi
          # Check checksums
          (cd /tmp && sha256sum --status -c sha256sum)
          if [ $? -ne 0 ]; then
            dialog --backtitle "`backtitle`" --title "Update Arc" --aspect 18 \
              --msgbox "Checksum do not match!" 0 0
            continue
          fi
          dialog --backtitle "`backtitle`" --title "Update Arc" --aspect 18 \
            --infobox "Installing new files" 0 0
          # Process update-list.yml
          while read F; do
            [ -f "${F}" ] && rm -f "${F}"
            [ -d "${F}" ] && rm -Rf "${F}"
          done < <(readConfigArray "remove" "/tmp/update-list.yml")
          while IFS=': ' read KEY VALUE; do
            if [ "${KEY: -1}" = "/" ]; then
              rm -Rf "${VALUE}"
              mkdir -p "${VALUE}"
              tar -zxf "/tmp/`basename "${KEY}"`.tgz" -C "${VALUE}"
            else
              mkdir -p "`dirname "${VALUE}"`"
              mv "/tmp/`basename "${KEY}"`" "${VALUE}"
            fi
          done < <(readConfigMap "replace" "/tmp/update-list.yml")
          dialog --backtitle "`backtitle`" --title "Update Arc" --aspect 18 \
            --yesno "Arc updated with success to ${TAG}!\nReboot?" 0 0
          [ $? -ne 0 ] && continue
          arpl-reboot.sh config
          exit
          ;;
        3)
          dialog --backtitle "`backtitle`" --title "Update addons" --aspect 18 \
            --infobox "Checking latest version" 0 0
          TAG=`curl --insecure -s https://api.github.com/repos/AuxXxilium/arc-addons/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3)}'`
          if [ $? -ne 0 -o -z "${TAG}" ]; then
            dialog --backtitle "`backtitle`" --title "Update addons" --aspect 18 \
              --msgbox "Error checking new version" 0 0
            continue
          fi
          dialog --backtitle "`backtitle`" --title "Update addons" --aspect 18 \
            --infobox "Downloading latest version: ${TAG}" 0 0
          STATUS=`curl --insecure -s -w "%{http_code}" -L "https://github.com/AuxXxilium/arc-addons/releases/download/${TAG}/addons.zip" -o /tmp/addons.zip`
          if [ $? -ne 0 -o ${STATUS} -ne 200 ]; then
            dialog --backtitle "`backtitle`" --title "Update addons" --aspect 18 \
              --msgbox "Error downloading new version" 0 0
            continue
          fi
          dialog --backtitle "`backtitle`" --title "Update addons" --aspect 18 \
            --infobox "Extracting latest version" 0 0
          rm -rf /tmp/addons
          mkdir -p /tmp/addons
          unzip /tmp/addons.zip -d /tmp/addons >/dev/null 2>&1
          dialog --backtitle "`backtitle`" --title "Update addons" --aspect 18 \
            --infobox "Installing new addons" 0 0
          rm -Rf "${ADDONS_PATH}/"*
          [ -f /tmp/addons/VERSION ] && cp -f /tmp/addons/VERSION ${ADDONS_PATH}/
          for PKG in `ls /tmp/addons/*.addon`; do
            ADDON=`basename ${PKG} | sed 's|.addon||'`
            rm -rf "${ADDONS_PATH}/${ADDON}"
            mkdir -p "${ADDONS_PATH}/${ADDON}"
            tar -xaf "${PKG}" -C "${ADDONS_PATH}/${ADDON}" >/dev/null 2>&1
          done
          DIRTY=1
          dialog --backtitle "`backtitle`" --title "Update addons" --aspect 18 \
            --msgbox "Addons updated with success! ${TAG}" 0 0
          ;;
        4)
          dialog --backtitle "`backtitle`" --title "Update LKMs" --aspect 18 \
            --infobox "Checking latest version" 0 0
          TAG=`curl --insecure -s https://api.github.com/repos/AuxXxilium/redpill-lkm/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3)}'`
          if [ $? -ne 0 -o -z "${TAG}" ]; then
            dialog --backtitle "`backtitle`" --title "Update LKMs" --aspect 18 \
              --msgbox "Error checking new version" 0 0
            continue
          fi
          dialog --backtitle "`backtitle`" --title "Update LKMs" --aspect 18 \
            --infobox "Downloading latest version: ${TAG}" 0 0
          STATUS=`curl --insecure -s -w "%{http_code}" -L "https://github.com/AuxXxilium/redpill-lkm/releases/download/${TAG}/rp-lkms.zip" -o /tmp/rp-lkms.zip`
          if [ $? -ne 0 -o ${STATUS} -ne 200 ]; then
            dialog --backtitle "`backtitle`" --title "Update LKMs" --aspect 18 \
              --msgbox "Error downloading latest version" 0 0
            continue
          fi
          dialog --backtitle "`backtitle`" --title "Update LKMs" --aspect 18 \
            --infobox "Extracting latest version" 0 0
          rm -rf "${LKM_PATH}/"*
          unzip /tmp/rp-lkms.zip -d "${LKM_PATH}" >/dev/null 2>&1
          DIRTY=1
          dialog --backtitle "`backtitle`" --title "Update LKMs" --aspect 18 \
            --msgbox "LKMs updated with success! ${TAG}" 0 0
          ;;
        5)
          dialog --backtitle "`backtitle`" --title "Update Modules" --aspect 18 \
            --infobox "Checking latest version" 0 0
          TAG="`curl -k -s "https://api.github.com/repos/AuxXxilium/arc-modules/releases/latest" | grep "tag_name" | awk '{print substr($2, 2, length($2)-3)}'`"
          if [ $? -ne 0 -o -z "${TAG}" ]; then
            dialog --backtitle "`backtitle`" --title "Update Modules" --aspect 18 \
              --msgbox "Error checking new version" 0 0
            continue
          fi
          dialog --backtitle "`backtitle`" --title "Update Modules" --aspect 18 \
            --infobox "Downloading latest version" 0 0
          STATUS="`curl -k -s -w "%{http_code}" -L "https://github.com/AuxXxilium/arc-modules/releases/download/${TAG}/modules.zip" -o "/tmp/modules.zip"`"
          if [ $? -ne 0 -o ${STATUS} -ne 200 ]; then
            dialog --backtitle "`backtitle`" --title "Update Modules" --aspect 18 \
              --msgbox "Error downloading latest version" 0 0
            continue
          fi
          rm "${MODULES_PATH}/"*
          unzip /tmp/modules.zip -d "${MODULES_PATH}" >/dev/null 2>&1
          # Rebuild modules if model/buildnumber is selected
          if [ -n "${PLATFORM}" -a -n "${KVER}" ]; then
            writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
            while read ID DESC; do
              writeConfigKey "modules.${ID}" "" "${USER_CONFIG_FILE}"
            done < <(getAllModules "${PLATFORM}" "${KVER}")
          fi
          DIRTY=1
          dialog --backtitle "`backtitle`" --title "Update Modules" --aspect 18 \
            --msgbox "Modules updated to ${TAG} with success!" 0 0
          ;;
        0) return ;;
      esac
    done
  else
    while true; do
      dialog --backtitle "`backtitle`" --menu "Choose an Option" 0 0 0 \
        1 "Full upgrade Loader" \
        0 "Exit" \
        2>${TMP_PATH}/resp
      [ $? -ne 0 ] && return
      case "`<${TMP_PATH}/resp`" in
        1)
          dialog --backtitle "`backtitle`" --title "Full upgrade Loader" --aspect 18 \
            --infobox "Checking latest version" 0 0
          ACTUALVERSION="v${ARPL_VERSION}"
          TAG="`curl --insecure -s https://api.github.com/repos/AuxXxilium/arc/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3)}'`"
          if [ $? -ne 0 -o -z "${TAG}" ]; then
            dialog --backtitle "`backtitle`" --title "Full upgrade Loader" --aspect 18 \
              --msgbox "Error checking new version" 0 0
            continue
          fi
          if [ "${ACTUALVERSION}" = "${TAG}" ]; then
            dialog --backtitle "`backtitle`" --title "Full upgrade Loader" --aspect 18 \
              --yesno "No new version. Actual version is ${ACTUALVERSION}\nForce update?" 0 0
            [ $? -ne 0 ] && continue
          fi
          dialog --backtitle "`backtitle`" --title "Full upgrade Loader" --aspect 18 \
            --infobox "Downloading latest version ${TAG}" 0 0
          # Download update file
          STATUS=`curl --insecure -w "%{http_code}" -L \
            "https://github.com/AuxXxilium/arc/releases/download/${TAG}/arc-${TAG}.img.zip" -o /tmp/arc-${TAG}.img.zip`
          if [ $? -ne 0 -o ${STATUS} -ne 200 ]; then
            dialog --backtitle "`backtitle`" --title "Full upgrade Loader" --aspect 18 \
              --msgbox "Error downloading update file" 0 0
            continue
          fi
          unzip -o /tmp/arc-${TAG}.img.zip -d /tmp
          if [ $? -ne 0 ]; then
            dialog --backtitle "`backtitle`" --title "Full upgrade Loader" --aspect 18 \
              --msgbox "Error extracting update file" 0 0
            continue
          fi
          if [ -f "${USER_CONFIG_FILE}" ]; then
            GENHASH=`cat /mnt/p1/user-config.yml | curl -s -F "content=<-" http://dpaste.com/api/v2/ | cut -c 19-`
            dialog --backtitle "`backtitle`" --title "Full upgrade Loader" --aspect 18 \
            --msgbox "Backup config successfull!\nWrite down your Code: ${GENHASH}\n\nAfter Reboot use: Backup - Restore with Code." 0 0
          else
            dialog --backtitle "`backtitle`" --title "Full upgrade Loader" --aspect 18 \
            --infobox "No config for Backup found!" 0 0
          fi
          dialog --backtitle "`backtitle`" --title "Full upgrade Loader" --aspect 18 \
            --infobox "Installing new Image" 0 0
          # Process complete update
          umount /mnt/p1 /mnt/p2 /mnt/p3
          dd if="/tmp/arc.img" of=`blkid | grep 'LABEL="ARPL3"' | cut -d3 -f1` bs=1M conv=fsync
          # Ask for Boot
          dialog --backtitle "`backtitle`" --title "Full upgrade Loader" --aspect 18 \
            --yesno "Arc updated with success to ${TAG}!\nReboot?" 0 0
          [ $? -ne 0 ] && continue
          arpl-reboot.sh config
          exit
          ;;
        0) return ;;
      esac
    done
}

###############################################################################
# Shows backup menu to user
function backupMenu() {
  NEXT="1"
  BUILDDONE="`readConfigKey "arc.builddone" "${USER_CONFIG_FILE}"`"
  if [ -n "${BUILDDONE}" ]; then
    while true; do
      dialog --backtitle "`backtitle`" --menu "Choose an Option" 0 0 0 \
        1 "Backup Config" \
        2 "Restore Config" \
        3 "Backup DSM Bootimage" \
        4 "Restore DSM Bootimage" \
        5 "Backup Config with Code" \
        6 "Restore Config with Code" \
        7 "Show Backup Path" \
        0 "Exit" \
        2>${TMP_PATH}/resp
      [ $? -ne 0 ] && return
      case "`<${TMP_PATH}/resp`" in
        1)
          dialog --backtitle "`backtitle`" --title "Backup Config" --aspect 18 \
            --infobox "Backup Config to ${BACKUPDIR}" 0 0
          if [ ! -d "${BACKUPDIR}" ]; then
            # Make backup dir
            mkdir ${BACKUPDIR}
          else
            # Clean old backup
            rm -f ${BACKUPDIR}/user-config.yml
          fi
          # Copy config to backup
          cp -f ${USER_CONFIG_FILE} ${BACKUPDIR}/user-config.yml
          if [ -f "${BACKUPDIR}/user-config.yml" ]; then
            dialog --backtitle "`backtitle`" --title "Backup Config" --aspect 18 \
              --msgbox "Backup complete" 0 0
          else
            dialog --backtitle "`backtitle`" --title "Backup Config" --aspect 18 \
              --msgbox "Backup error" 0 0
          fi
          ;;
        2)
          dialog --backtitle "`backtitle`" --title "Restore Config" --aspect 18 \
            --infobox "Restore Config from ${BACKUPDIR}" 0 0
          if [ -f "${BACKUPDIR}/user-config.yml" ]; then
            # Copy config back to location
            cp -f ${BACKUPDIR}/user-config.yml ${USER_CONFIG_FILE}
            dialog --backtitle "`backtitle`" --title "Restore Config" --aspect 18 \
              --msgbox "Restore complete" 0 0
          else
            dialog --backtitle "`backtitle`" --title "Restore Config" --aspect 18 \
              --msgbox "No Config Backup found" 0 0
          fi
          CONFDONE="`readConfigKey "arc.confdone" "${USER_CONFIG_FILE}"`"
          deleteConfigKey "arc.builddone" "${USER_CONFIG_FILE}"
          BUILDDONE="`readConfigKey "arc.builddone" "${USER_CONFIG_FILE}"`"
          ;;
        3)
          dialog --backtitle "`backtitle`" --title "Backup DSM Bootimage" --aspect 18 \
            --infobox "Backup DSM Bootimage to ${BACKUPDIR}" 0 0
          if [ ! -d "${BACKUPDIR}" ]; then
            # Make backup dir
            mkdir ${BACKUPDIR}
          else
            # Clean old backup
            rm -f ${BACKUPDIR}/dsm-backup.tar
          fi
          # Copy files to backup
          cp -f ${USER_CONFIG_FILE} ${BACKUPDIR}/user-config.yml
          cp -f ${CACHE_PATH}/zImage-dsm ${BACKUPDIR}
          cp -f ${CACHE_PATH}/initrd-dsm ${BACKUPDIR}
          # Compress backup
          tar -cvf ${BACKUPDIR}/dsm-backup.tar ${BACKUPDIR}/
          # Clean temp files from backup dir
          rm -f ${BACKUPDIR}/user-config.yml
          rm -f ${BACKUPDIR}/zImage-dsm
          rm -f ${BACKUPDIR}/initrd-dsm
          if [ -f "${BACKUPDIR}/dsm-backup.tar" ]; then
            dialog --backtitle "`backtitle`" --title "Backup DSM Bootimage" --aspect 18 \
              --msgbox "Backup complete" 0 0
          else
            dialog --backtitle "`backtitle`" --title "Backup DSM Bootimage" --aspect 18 \
              --msgbox "Backup error" 0 0
          fi
          ;;
        4)
          dialog --backtitle "`backtitle`" --title "Restore DSM Bootimage" --aspect 18 \
            --infobox "Restore DSM Bootimage from ${BACKUPDIR}" 0 0
          if [ -f "${BACKUPDIR}/dsm-backup.tar" ]; then
            # Uncompress backup
            tar -xvf ${BACKUPDIR}/dsm-backup.tar -C /
            # Copy files to locations
            cp -f ${BACKUPDIR}/user-config.yml ${USER_CONFIG_FILE}
            cp -f ${BACKUPDIR}/zImage-dsm ${CACHE_PATH}
            cp -f ${BACKUPDIR}/initrd-dsm ${CACHE_PATH}
            # Clean temp files from backup dir
            rm -f ${BACKUPDIR}/user-config.yml
            rm -f ${BACKUPDIR}/zImage-dsm
            rm -f ${BACKUPDIR}/initrd-dsm
            CONFDONE="`readConfigKey "arc.confdone" "${USER_CONFIG_FILE}"`"
            BUILDDONE="`readConfigKey "arc.builddone" "${USER_CONFIG_FILE}"`"
            dialog --backtitle "`backtitle`" --title "Restore DSM Bootimage" --aspect 18 \
              --msgbox "Restore complete" 0 0
          else
            dialog --backtitle "`backtitle`" --title "Restore DSM Bootimage" --aspect 18 \
              --msgbox "No DSM Bootimage Backup found" 0 0
          fi
          ;;
        5)
          dialog --backtitle "`backtitle`" --title "Backup Config with Code" \
              --infobox "Write down your Code for Restore!" 0 0
          if [ -f "${USER_CONFIG_FILE}" ]; then
            GENHASH=`cat /mnt/p1/user-config.yml | curl -s -F "content=<-" http://dpaste.com/api/v2/ | cut -c 19-`
            dialog --backtitle "`backtitle`" --title "Backup Config with Code" --msgbox "Your Code: ${GENHASH}" 0 0
          else
            dialog --backtitle "`backtitle`" --title "Backup Config with Code" --msgbox "No Config for Backup found!" 0 0
          fi
          ;;
        6)
          while true; do
            dialog --backtitle "`backtitle`" --title "Restore Config with Code" \
              --inputbox "Type your Code here!" 0 0 \
              2>${TMP_PATH}/resp
            RET=$?
            [ ${RET} -ne 0 ] && break 2
            GENHASH="`<"${TMP_PATH}/resp"`"
            [ ${#GENHASH} -eq 9 ] && break
            dialog --backtitle "`backtitle`" --title "Restore with Code" --msgbox "Invalid Code" 0 0
          done
          curl -k https://dpaste.com/${GENHASH}.txt > /tmp/user-config.yml
          mv -f /tmp/user-config.yml /mnt/p1/user-config.yml
          ;;
        7)
          dialog --backtitle "`backtitle`" --title "Backup Path" --aspect 18 \
            --msgbox "Open in Explorer: \\\\${IP}\arpl\p3\backup" 0 0
          ;;
        0) return ;;
      esac
    done
  else
    while true; do
      dialog --backtitle "`backtitle`" --menu "Choose an Option" 0 0 0 \
        1 "Restore Config" \
        2 "Restore DSM Bootimage" \
        3 "Restore Config with Code" \
        4 "Show Backup Path" \
        0 "Exit" \
        2>${TMP_PATH}/resp
      [ $? -ne 0 ] && return
      case "`<${TMP_PATH}/resp`" in
        1)
          dialog --backtitle "`backtitle`" --title "Restore Config" --aspect 18 \
            --infobox "Restore Config from ${BACKUPDIR}" 0 0
          if [ -f "${BACKUPDIR}/user-config.yml" ]; then
            # Copy config back to location
            cp -f ${BACKUPDIR}/user-config.yml ${USER_CONFIG_FILE}
            dialog --backtitle "`backtitle`" --title "Restore Config" --aspect 18 \
              --msgbox "Restore complete" 0 0
          else
            dialog --backtitle "`backtitle`" --title "Restore Config" --aspect 18 \
              --msgbox "No Config Backup found" 0 0
          fi
          CONFDONE="`readConfigKey "arc.confdone" "${USER_CONFIG_FILE}"`"
          deleteConfigKey "arc.builddone" "${USER_CONFIG_FILE}"
          BUILDDONE="`readConfigKey "arc.builddone" "${USER_CONFIG_FILE}"`"
          ;;
        2)
          dialog --backtitle "`backtitle`" --title "Restore DSM Bootimage" --aspect 18 \
            --infobox "Restore DSM Bootimage from ${BACKUPDIR}" 0 0
          if [ -f "${BACKUPDIR}/dsm-backup.tar" ]; then
            # Uncompress backup
            tar -xvf ${BACKUPDIR}/dsm-backup.tar -C /
            # Copy files to locations
            cp -f ${BACKUPDIR}/user-config.yml ${USER_CONFIG_FILE}
            cp -f ${BACKUPDIR}/zImage-dsm ${CACHE_PATH}
            cp -f ${BACKUPDIR}/initrd-dsm ${CACHE_PATH}
            # Clean temp files from backup dir
            rm -f ${BACKUPDIR}/user-config.yml
            rm -f ${BACKUPDIR}/zImage-dsm
            rm -f ${BACKUPDIR}/initrd-dsm
            CONFDONE="`readConfigKey "arc.confdone" "${USER_CONFIG_FILE}"`"
            BUILDDONE="`readConfigKey "arc.builddone" "${USER_CONFIG_FILE}"`"
            dialog --backtitle "`backtitle`" --title "Restore DSM Bootimage" --aspect 18 \
              --msgbox "Restore complete" 0 0
          else
            dialog --backtitle "`backtitle`" --title "Restore DSM Bootimage" --aspect 18 \
              --msgbox "No Loader Backup found" 0 0
          fi
          ;;
        3)
          while true; do
            dialog --backtitle "`backtitle`" --title "Restore with Code" \
              --inputbox "Type your Code here!" 0 0 \
              2>${TMP_PATH}/resp
            RET=$?
            [ ${RET} -ne 0 ] && break 2
            GENHASH="`<"${TMP_PATH}/resp"`"
            [ ${#GENHASH} -eq 9 ] && break
            dialog --backtitle "`backtitle`" --title "Restore with Code" --msgbox "Invalid Code" 0 0
          done
          curl -k https://dpaste.com/${GENHASH}.txt > /tmp/user-config.yml
          mv -f /tmp/user-config.yml /mnt/p1/user-config.yml
          CONFDONE="`readConfigKey "arc.confdone" "${USER_CONFIG_FILE}"`"
          BUILDDONE="`readConfigKey "arc.builddone" "${USER_CONFIG_FILE}"`"
          dialog --backtitle "`backtitle`" --title "Restore with Code" --aspect 18 \
              --msgbox "Restore complete" 0 0
          ;;
        4)
          dialog --backtitle "`backtitle`" --title "Backup Path" --aspect 18 \
            --msgbox "Open in Explorer: \\\\${IP}\arpl\p3\backup" 0 0
          ;;
        0) return ;;
      esac
    done
  fi
}

###############################################################################
# Try to recovery a DSM already installed
function tryRecoveryDSM() {
  dialog --backtitle "`backtitle`" --title "Try to recover DSM" --aspect 18 \
    --infobox "Trying to recover a DSM installed system" 0 0
  if findAndMountDSMRoot; then
    MODEL=""
    BUILD=""
    if [ -f "${DSMROOT_PATH}/.syno/patch/VERSION" ]; then
      eval `cat ${DSMROOT_PATH}/.syno/patch/VERSION | grep unique`
      eval `cat ${DSMROOT_PATH}/.syno/patch/VERSION | grep base`
      if [ -n "${unique}" ] ; then
        while read F; do
          M="`basename ${F}`"
          M="${M::-4}"
          UNIQUE=`readModelKey "${M}" "unique"`
          [ "${unique}" = "${UNIQUE}" ] || continue
          # Found
          modelMenu "${M}"
        done < <(find "${MODEL_CONFIG_PATH}" -maxdepth 1 -name \*.yml | sort)
        if [ -n "${MODEL}" ]; then
          buildMenu ${base}
          if [ -n "${BUILD}" ]; then
            cp "${DSMROOT_PATH}/.syno/patch/zImage" "${SLPART_PATH}"
            cp "${DSMROOT_PATH}/.syno/patch/rd.gz" "${SLPART_PATH}"
            MSG="Found a installation:\nModel: ${MODEL}\nBuildnumber: ${BUILD}"
            SN=`_get_conf_kv SN "${DSMROOT_PATH}/etc/synoinfo.conf"`
            if [ -n "${SN}" ]; then
              writeConfigKey "sn" "${SN}" "${USER_CONFIG_FILE}"
              MSG+="\nSerial: ${SN}"
            fi
            dialog --backtitle "`backtitle`" --title "Try to recover DSM" \
              --aspect 18 --msgbox "${MSG}" 0 0
          fi
        fi
      fi
    fi
  else
    dialog --backtitle "`backtitle`" --title "Try recovery DSM" --aspect 18 \
      --msgbox "Unfortunately I couldn't mount the DSM partition!" 0 0
  fi
}

 ###############################################################################
# allow downgrade dsm version
function downgradeMenu() {
  MSG=""
  MSG+="This feature will allow you to downgrade the installation by removing the VERSION file from the first partition of all disks.\n"
  MSG+="Therefore, please insert all disks before continuing.\n"
  MSG+="Warning:\nThis operation is irreversible. Please backup important data. Do you want to continue?"
  dialog --backtitle "`backtitle`" --title "Allow downgrade installation" \
      --yesno "${MSG}" 0 0
  [ $? -ne 0 ] && return
  (
    mkdir -p /tmp/sdX1
    for I in `ls /dev/sd*1 2>/dev/null | grep -v ${LOADER_DISK}1`; do
      mount ${I} /tmp/sdX1
      [ -f "/tmp/sdX1/etc/VERSION" ] && rm -f "/tmp/sdX1/etc/VERSION"
      [ -f "/tmp/sdX1/etc.defaults/VERSION" ] && rm -f "/tmp/sdX1/etc.defaults/VERSION"
      sync
      umount ${I}
    done
    rm -rf /tmp/sdX1
  ) | dialog --backtitle "`backtitle`" --title "Allow downgrade installation" \
      --progressbox "Removing ..." 20 70
  MSG="$(TEXT "Remove VERSION file for all disks completed.")"
  dialog --backtitle "`backtitle`" --colors --aspect 18 \
    --msgbox "${MSG}" 0 0
}
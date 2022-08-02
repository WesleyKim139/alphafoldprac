#!/bin/bash
# edited by Yinying Yao
set -e
db_path=$(readlink -f $1)

if [[ "$(which rsync)" == "" ]];then
  echo "Rsync not available."
  if [[ "$(which yum)" != "" ]];then
    LINUX_DIST="REDHAT"
    sudo yum install rsync -y
  elif [[ "$(which apt)" != "" ]];then
    LINUX_DIST="DEBIAN"
    sudo apt install rsync -y
  else
    echo "Error: Please install rsync by yourself."
    exit 1
  fi
fi

mkdir -p $db_path

rsync_configuration="# /etc/rsyncd: configuration file for rsync daemon mode

# See rsyncd.conf man page for more options.

uid = nobody
gid = nobody
use chroot = no
max connections = 0
lock file=/var/run/rsyncd.lock
log file = /var/log/rsyncd.log
exclude = lost+found/
transfer logging = yes
timeout = 900
ignore nonreadable = yes
dont compress   = *.gz *.tgz *.zip *.z *.Z *.rpm *.deb *.bz2

[db]
path = ${db_path}
comment=dbs
ignore errors
read only=yes
write only=no
list=no
#auth users=user
#secrets file=/etc/rsyncd.passwd

hosts allow=* "

sudo systemctl start rsyncd.service
sudo systemctl enable rsyncd.service
echo ${rsync_configuration} >/etc/rsyncd.conf
rsync -daemon -config=/etc/rsyncd.conf
sudo systemctl restart rsyncd.service

echo "----------------------------------------------------------------------------"
echo "Modifying firewall configuration in expected linux distribution ${LINUX_DIST} ... "
if [[ "$LINUX_DIST" == "CENTOS" ]]; then
  sudo firewall-cmd --zone=public --add-port=873/tcp --permanent || exit 1
elif [[ "$LINUX_DIST" == "DEBIAN" ]]; then
  sudo ufw allow 873 && sudo ufw reload || exit 1
fi

echo "----------------------------------------------------------------------------"
echo "Now we start to synchronize from original mirrors ..."

mkdir --parents ${db_path}

echo "Trying to sync with PDBj ..." && \
MIRROR="PDBj" && \
MIRROR_CMD="rsync --recursive --links --perms --times --compress --info=progress2 --delete data.pdbj.org::ftp_data/structures/divided/mmCIF/ ${db_path}/pdb_mmcif/raw/" && \
echo "${MIRROR_CMD}" && eval "${MIRROR_CMD}" || \
echo "Trying to sync with EBI ..." && MIRROR="EBI" && \
MIRROR_CMD="rsync --recursive --links --perms --times --compress --info=progress2 --delete rsync.ebi.ac.uk::ftp_data/structures/divided/mmCIF/ ${db_path}/pdb_mmcif/raw/" && \
echo "${MIRROR_CMD}" && eval "${MIRROR_CMD}" || \
echo "Trying to sync with RCSB PDB ..." && MIRROR="RCSB" && \
MIRROR_CMD="rsync --recursive --links --perms --times --compress --info=progress2 --delete --port=33444 rsync.rcsb.org::ftp_data/structures/divided/mmCIF/  ${db_path}/pdb_mmcif/raw/" &&
echo "${MIRROR_CMD}" && eval "${MIRROR_CMD}" || echo Failed to run all rsync tests && exit 1
echo "----------------------------------------------------------------------------"
echo "Done! Mirror site: ${MIRROR}"
echo "The following command will be executed every Friday:"
echo "${MIRROR_CMD}"

echo "----------------------------------------------------------------------------"
echo "Now we create a crontab task."
CRONTAB_CMD="#!/bin/bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH
${MIRROR_CMD}
echo \"----------------------------------------------------------------------------\"
endDate=\`date +\"%Y-%m-%d %H:%M:%S\"\`
echo \"★[\${endDate}] Successful\"
echo \"----------------------------------------------------------------------------\"
"

echo "${CRONTAB_CMD}" > "${db_path}/pdb_mmcif_rsync.sh"
touch /var/spool/cron/$(whoami)
echo "30 16 * * 5 ${db_path}/pdb_mmcif_rsync.sh" >> /var/spool/cron/$(whoami)





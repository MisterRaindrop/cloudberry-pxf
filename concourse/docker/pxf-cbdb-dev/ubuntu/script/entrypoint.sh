#!/bin/bash
set -e
set -x

sudo apt-get update && \
    sudo apt-get install -y wget lsb-release locales openjdk-11-jre-headless openjdk-8-jre-headless iproute2 sudo  && \
    sudo locale-gen en_US.UTF-8 && \
    sudo locale-gen ru_RU.CP1251 && \
    sudo locale-gen ru_RU.UTF-8 && \
    sudo update-locale LANG=en_US.UTF-8

export LANG=en_US.UTF-8
export LANGUAGE=en_US:en
export LC_ALL=en_US.UTF-8

sudo apt-get install -y maven unzip openssh-server

sudo localedef -c -i ru_RU -f CP1251 ru_RU.CP1251

sudo ssh-keygen -A && \
sudo bash -c 'echo "PasswordAuthentication yes" >> /etc/ssh/sshd_config' && \
sudo mkdir -p /etc/ssh/sshd_config.d && \
sudo touch /etc/ssh/sshd_config.d/pxf-automation.conf && \
sudo bash -c 'echo "KexAlgorithms +diffie-hellman-group-exchange-sha1,diffie-hellman-group14-sha1,diffie-hellman-group1-sha1" >> /etc/ssh/sshd_config.d/pxf-automation.conf' && \
sudo bash -c 'echo "HostKeyAlgorithms +ssh-rsa,ssh-dss" >> /etc/ssh/sshd_config.d/pxf-automation.conf' && \
sudo bash -c 'echo "PubkeyAcceptedAlgorithms +ssh-rsa,ssh-dss" >> /etc/ssh/sshd_config.d/pxf-automation.conf'

sudo usermod -a -G sudo gpadmin && \
echo "gpadmin:cbdb@123" | sudo chpasswd && \
echo "gpadmin        ALL=(ALL)       NOPASSWD: ALL" | sudo tee -a /etc/sudoers && \
echo "root           ALL=(ALL)       NOPASSWD: ALL" | sudo tee -a /etc/sudoers


mkdir -p /home/gpadmin/.ssh && \
sudo chown -R gpadmin:gpadmin /home/gpadmin/.ssh && \
sudo -u gpadmin ssh-keygen -t rsa -b 4096 -m PEM -C gpadmin -f /home/gpadmin/.ssh/id_rsa -P "" && \
sudo -u gpadmin bash -c 'cat /home/gpadmin/.ssh/id_rsa.pub >> /home/gpadmin/.ssh/authorized_keys' && \
sudo -u gpadmin chmod 0600 /home/gpadmin/.ssh/authorized_keys

# ----------------------------------------------------------------------
# Start SSH daemon and setup for SSH access
# ----------------------------------------------------------------------
# The SSH daemon is started to allow remote access to the container via
# SSH. This is useful for development and debugging purposes. If the SSH
# daemon fails to start, the script exits with an error.
# ----------------------------------------------------------------------
if [ ! -d /var/run/sshd ]; then
   sudo mkdir /var/run/sshd
   sudo chmod 0755 /var/run/sshd
fi
if ! sudo /usr/sbin/sshd; then
    echo "Failed to start SSH daemon"
    exit 1
fi

# ----------------------------------------------------------------------
# Remove /run/nologin to allow logins for all users via SSH
# ----------------------------------------------------------------------
sudo rm -rf /run/nologin

# ----------------------------------------------------------------------
# Configure /home/gpadmin
# ----------------------------------------------------------------------
mkdir -p /home/gpadmin/.ssh/
ssh-keyscan -t rsa cdw > /home/gpadmin/.ssh/known_hosts
chown -R gpadmin:gpadmin /home/gpadmin/.ssh/

# ----------------------------------------------------------------------
# Build Cloudberry
# ----------------------------------------------------------------------
./build_cloudberrry.sh


# ----------------------------------------------------------------------
# Build pxf
# ----------------------------------------------------------------------
./build_pxf.sh
source ./pxf-env.sh
# ----------------------------------------------------------------------
# Prepare PXF
# ----------------------------------------------------------------------
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export PATH="$PXF_HOME/bin:$PATH"
export PXF_JVM_OPTS="-Xmx512m -Xms256m"
export PXF_HOST=localhost # 0.0.0.0  # listen on all interfaces

# Prepare a new $PXF_BASE directory on each Greenplum Database host.
# - create directory structure in $PXF_BASE
# - copy configuration files from $PXF_HOME/conf to $PXF_BASE/conf
/usr/local/pxf/bin/pxf cluster prepare

# Use Java 11:
echo "JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64" >> $PXF_BASE/conf/pxf-env.sh
# Configure PXF to listen on all interfaces
sed -i 's/# server.address=localhost/server.address=0.0.0.0/' $PXF_BASE/conf/pxf-application.properties
# add property to allow dynamic test: profiles that are used when testing against FDW
echo -e "\npxf.profile.dynamic.regex=test:.*" >> $PXF_BASE/conf/pxf-application.properties
# set up pxf configs from templates
cp -v $PXF_HOME/templates/{hdfs,mapred,yarn,core,hbase,hive}-site.xml $PXF_BASE/servers/default

# Register PXF extension in Greenplum
# - Copy the PXF extension control file from the PXF installation on each host to the Greenplum installation on the host
/usr/local/pxf/bin/pxf cluster register
# # Start PXF
/usr/local/pxf/bin/pxf cluster start

# ----------------------------------------------------------------------
# Prepare Hadoop
# ----------------------------------------------------------------------
# FIXME: reuse old scripts
cd /home/gpadmin/workspace/cloudberry-pxf/automation
make symlink_pxf_jars
cp /home/gpadmin/automation_tmp_lib/pxf-hbase.jar $GPHD_ROOT/hbase/lib/

$GPHD_ROOT/bin/init-gphd.sh
$GPHD_ROOT/bin/start-gphd.sh

# --------------------------------------------------------------------
# Run tests
# --------------------------------------------------------------------
# create GOCACHE directory for gpadmin user
sudo mkdir -p /home/gpadmin/.cache/go-build
sudo chown -R gpadmin:gpadmin /home/gpadmin/.cache
sudo chmod -R 755 /home/gpadmin/.cache
# create .m2 cache directory
sudo mkdir -p /home/gpadmin/.m2
sudo chown -R gpadmin:gpadmin /home/gpadmin/.m2
sudo chmod -R 755 /home/gpadmin/.m2

# make without arguments runs all tests
cd /home/gpadmin/workspace/cloudberry-pxf/automation
make

# Keep container running
#tail -f /dev/null
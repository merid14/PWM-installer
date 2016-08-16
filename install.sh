#!/bin/bash
#set -e
# =====================================================================
# PWM Installer
# Authors: Walter Wahlstedt
#
# v1.0|08/16/2016:  PWM Installer for Centos 7
#
# =====================================================================

# ensure running as root
if [ "$(id -u)" != "0" ]; then
  exec sudo "$0" "$@"
fi
clear

name="pwm"
hostname="$(hostname)"
fqdn="$(hostname --fqdn)"
installed="$webdir/$name/.installed"
ans=default
hosts=/etc/hosts
file=master.zip
tmp=/tmp/$name
date="$(date '+%Y-%b-%d')"
backup=/opt/$name/backup/$date
log="$(find /var/log/ -type f -name "$name-install.log")"
tomcatfile=/etc/systemd/system/tomcat.service

function isinstalled {
  if yum list installed "$@" >/dev/null 2>&1; then
    true
  else
    false
  fi
}

#  Lets find what distro we are using and what version
distro="$(cat /proc/version)"
if grep -q centos <<<$distro; then
        for f in $(find /etc -type f -maxdepth 1 \( ! -wholename /etc/os-release ! -wholename /etc/lsb-release -wholename /etc/\*release -o -wholename /etc/\*version \) 2> /dev/null);
        do
                distro="${f:5:${#f}-13}"
        done;
        if [ "$distro" = "centos" ] || [ "$distro" = "redhat" ]; then
                distro+="$(rpm -q --qf "%{VERSION}" $(rpm -q --whatprovides redhat-release))"
        fi
fi

echo "
 _______  ____      ____  ____    ____
|_   __ \|_  _|    |_  _||_   \  /   _|
  | |__) | \ \  /\  / /    |   \/   |
  |  ___/   \ \/  \/ /     | |\  /| |
 _| |_       \  /\  /     _| |_\/_| |_
|_____|       \/  \/     |_____||_____|


"

echo ""
echo ""
echo "  Welcome to $name Installer for Centos and Debian!"
echo ""

case $distro in
        *Ubuntu*|*Debian*)
                echo "  The installer has detected Ubuntu/Debian as the OS."
                distro=debian
                ;;
        *centos6*|*redhat6*)
                echo "  The installer has detected $distro as the OS."
                distro=centos6
                ;;
        *centos7*|*redhat7*)
                echo "  The installer has detected $distro as the OS."
                distro=centos7
                ;;
        *)
                echo "  The installer was unable to determine your OS. Exiting for safety."
                exit
                ;;
esac

echo ""
echo ""
echo "## Setting up directories."
rm -rf $tmp/
mkdir -p $tmp
mkdir -p /opt/tomcat
cd $tmp

echo "##  Installing Required Packages.";
PACKAGES="java-1.8.0-openjdk java-1.8.0-openjdk-devel tomcat-native"

for p in $PACKAGES;do
        if isinstalled $p;then
                echo " ##" $p "Installed"
        else
                echo -n " ##" $p "Installing... "
                yum -y install $p >> /var/log/$name-install.log 2>&1
        echo "";
        fi
done;

echo "##  Getting tomcat installer."
echo "    Browse to http://apache.claz.org/tomcat/tomcat-8/"
echo -n "    Input the latest release number (ex:8.0.36) : "
read tomcatlink

wget http://apache.claz.org/tomcat/tomcat-8/v$tomcatlink/bin/apache-tomcat-$tomcatlink.tar.gz >> /var/log/$name-update.log 2>&1
tar xvf apache-tomcat-*.tar.gz -C /opt/tomcat --strip-components=1 >> /var/log/$name-update.log 2>&1
cd /opt/tomcat

echo "##  Creating group and setting permissions for tomcat."
groupadd tomcat
useradd -M -s /bin/nologin -g tomcat -d /opt/tomcat tomcat
mkdir /opt/pwm-data
chmod g+rwx conf
chmod g+r /opt/tomcat/conf/*
chown -R tomcat /opt/tomcat/webapps/ /opt/tomcat/work/ /opt/tomcat/temp/ /opt/tomcat/logs/
chgrp -R tomcat /opt/tomcat/conf /opt/tomcat/bin
chown -R tomcat:tomcat /opt/pwm-data


echo "##  Creating tomcat service."
if [ -f "$tomcatfile" ]; then
        echo "  Service already exists. $tomcatfile"
        echo ""
else
        echo "  Creating service file: $tomcatfile"
        echo ""
        cat > $tomcatfile <<"EOF" ||:
# Systemd unit file for tomcat
[Unit]
Description=Apache Tomcat Web Application Container
After=syslog.target network.target

[Service]
Type=forking

Environment=JAVA_HOME=/usr/lib/jvm/jre
Environment=CATALINA_PID=/opt/tomcat/temp/tomcat.pid
Environment=CATALINA_HOME=/opt/tomcat
Environment=CATALINA_BASE=/opt/tomcat
Environment='CATALINA_OPTS=-Xms512M -Xmx1024M -server -XX:+UseParallelGC'
Environment='JAVA_OPTS=-Djava.awt.headless=true -Djava.security.egd=file:/dev/./urandom'

ExecStart=/opt/tomcat/bin/startup.sh
ExecStop=/bin/kill -15 $MAINPID

User=tomcat
Group=tomcat

[Install]
WantedBy=multi-user.target
EOF
fi

systemctl daemon-reload
systemctl start tomcat
systemctl enable tomcat

echo "## Setting up user for tomcat manager."
echo "    User: admin"
echo -n " Q. What would you like to set the password to: "
    read -r tomcatpw
echo ""

## this is to setup user for tomcat manager
cat >> /opt/tomcat/conf/tomcat-users.xml <<EOF
  <role rolename="admin-gui"/>
  <role rolename="manager-gui"/>
  <user username="ucadmin" password="$tomcatpw" roles="admin-gui,manager-gui"/>
EOF

systemctl restart tomcat
echo "## Tomcat install complete."
echo ""
echo "------------------------------------------------------------------------------------"
echo ""
echo "## Make sure you setup ssl certificat files."
echo "    You can get the cert files from another web server"
echo "    The folloing is an example."
echo ""
echo "vim /opt/tomcat/conf/server.xml"
echo ""
echo '    <Connector protocol="org.apache.coyote.http11.Http11AprProtocol"'
echo '                           port="8443" maxThreads="200"'
echo '                   scheme="https" secure="true" SSLEnabled="true"'
echo '                   SSLCertificateFile="/etc/httpd/ssl/CertificateFile.crt"'
echo '                   SSLCertificateKeyFile="/etc/httpd/ssl/KeyFile.key"                                                                                                                                                             '
echo '                   SSLCertificateChainFile="/etc/httpd/ssl/ChainFile.crt"'
echo '                   SSLCACertificateFile="/etc/httpd/ssl/CACertificateFile.crt"'
echo '                   SSLVerifyClient="optional" SSLProtocol="TLSv1+TLSv1.1+TLSv1.2"/>'
echo ""
echo ""

echo "  ## Starting $name installer."
echo "    Browse to http://www.pwm-project.org/artifacts/pwm/"
echo -n "    Get the latest release link and paste here: "
read pwmlink

cd $tmp
wget $pwmlink
file=$(ls | grep *.zip)
pwmlink=$(sed "s,http://www.pwm-project.org/artifacts/pwm/,,g" <<< $pwmlink)

unzip -qo $tmp/$file -d $tmp/
cp -u $tmp/pwm.war /opt/tomcat/webapps
cd /opt/tomcat/webapps
chown tomcat:tomcat pwm.war
systemctl restart tomcat

sed -i "s,<param-value>unspecified</param-value>,<param-value>/opt/pwm-data</param-value>,g" /opt/tomcat/webapps/pwm/WEB-INF/web.xml

echo "  ## Cleaning Up."
echo ""
rm -rf $tmp

echo ""
echo "  ## PWM Installed."
echo "   visit https://$fqdn:8443/pwm"

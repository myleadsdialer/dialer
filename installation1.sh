#!/bin/bash

# ViciBox Automation Setup Script - Interactive Version
# Target: ViciBox 11/12

# ---------------------------------------------------------
# 1. Interactive Selection (Domain & Superadmin Password)
# ---------------------------------------------------------
clear
echo "====================================================="
echo "        VICIBOX AUTOMATION SETUP SCRIPT"
echo "====================================================="
echo ""
read -p "Enter your Domain/FQDN (e.g., dialer.example.com): " DOMAIN

if [ -z "$DOMAIN" ]; then
    echo "Error: Domain cannot be empty. Exiting."
    exit 1
fi

# New interactive password prompt
read -s -p "Enter new password for 'superadmin': " ADMIN_PASS
echo "" # New line after silent input

if [ -z "$ADMIN_PASS" ]; then
    echo "Error: Password cannot be empty. Exiting."
    exit 1
fi

echo ""
echo "Configuration Details:"
echo " - Domain: $DOMAIN"
echo " - Admin User: superadmin"
echo " - SSH Port: 51962"
echo " - SIP/PJSIP Ports: 50961 / 50962"
echo " - Dynamic Portal Port: 666"
echo ""
read -p "Does this look correct? (y/n): " confirm
if [[ $confirm != [yY] ]]; then
    echo "Aborting."
    exit 1
fi

# ---------------------------------------------------------
# 2. Variables
# ---------------------------------------------------------
SSH_PORT="51962"
DYNAMIC_PORT="666"
SIP_PORT="50961"
PJSIP_PORT="50962"
DB_PASS="1234"

# ---------------------------------------------------------
# 3. System Updates & Timezone
# ---------------------------------------------------------
echo "--- Updating system packages ---"
zypper refresh && zypper update -y
vicibox-timezone

# ---------------------------------------------------------
# 4. Apache & SSH Configuration
# ---------------------------------------------------------
echo "--- Configuring Apache and SSH ---"
sed -i "1i ServerName localhost\nServerName $DOMAIN" /etc/apache2/httpd.conf
sed -i "s/#Port 22/Port $SSH_PORT/g" /etc/ssh/sshd_config

systemctl enable --now firewalld
firewall-cmd --zone=external --add-port=$SSH_PORT/tcp --permanent
firewall-cmd --zone=public --add-port=$SSH_PORT/tcp --permanent

sed -i '49s|^|#|' /usr/bin/VB-firewall
systemctl enable apache2.service
systemctl start apache2.service

# ---------------------------------------------------------
# 5. ViciBox Express & SSL
# ---------------------------------------------------------
echo "--- Starting ViciBox Express Installation ---"
vicibox-express
echo "--- Starting SSL Configuration ---"
vicibox-ssl

# ---------------------------------------------------------
# 6. Asterisk Port Changes
# ---------------------------------------------------------
echo "--- Updating SIP Ports ---"
sed -i "s/bindport=5060/bindport=$SIP_PORT/" /etc/asterisk/sip.conf
sed -i "s/bind.*= 0.0.0.0:5061/bind = 0.0.0.0:$PJSIP_PORT/" /etc/asterisk/pjsip.conf

# ---------------------------------------------------------
# 7. Web Interface Options
# ---------------------------------------------------------
cp /srv/www/htdocs/agc/options-example.php /srv/www/htdocs/agc/options.php
sed -i "s/\$user_login_first[[:space:]]*=[[:space:]]*'0';/\$user_login_first = '1';/" /srv/www/htdocs/agc/options.php 

# ---------------------------------------------------------
# 8. Database Permissions & Admin Setup (Updated)
# ---------------------------------------------------------
echo "--- Configuring Database Settings ---"
mysql -u cron -p$DB_PASS asterisk -e "UPDATE system_settings SET allow_ip_lists='1';"
mysql -u cron -p$DB_PASS asterisk -e "UPDATE vicidial_ip_lists SET active='Y' WHERE ip_list_id IN ('ViciWhite','ViciBlack');"
mysql -u cron -p$DB_PASS asterisk -e "UPDATE vicidial_users SET modify_ip_lists='1', ignore_ip_list='0' WHERE user='superadmin';"

# Use the ADMIN_PASS variable for the superadmin password
mysql -u cron -p$DB_PASS asterisk -e "UPDATE asterisk.vicidial_users SET user='superadmin',pass='$ADMIN_PASS' WHERE user='6666';"

# Grant Admin Access
mysql -u cron -p$DB_PASS asterisk -e "UPDATE asterisk.vicidial_users SET delete_users='1',delete_user_groups='1',delete_lists='1',delete_campaigns='1',delete_ingroups='1',delete_remote_agents='1',load_leads='1',campaign_detail='1',ast_admin_access='1',ast_delete_phones='1',delete_scripts='1',modify_leads='1',change_agent_campaign='1',agent_choose_ingroups='1',scheduled_callbacks='1',vicidial_recording='1',vicidial_transfers='1',delete_filters='1',alter_agent_interface_options='1',delete_call_times='1',modify_call_times='1',modify_users='1',modify_campaigns='1',modify_lists='1',modify_scripts='1',modify_filters='1',modify_ingroups='1',modify_usergroups='1',modify_remoteagents='1',modify_servers='1',view_reports='1',qc_user_level='1',add_timeclock_log='1',modify_timeclock_log='1',delete_timeclock_log='1',vdc_agent_api_access='1',modify_inbound_dids='1',delete_inbound_dids='1',download_lists='1',manager_shift_enforcement_override='1',export_reports='1',delete_from_dnc='1',callcard_admin='1',agent_choose_blended='1',custom_fields_modify='1',modify_shifts='1',modify_phones='1',modify_carriers='1',modify_labels='1',modify_statuses='1',modify_voicemail='1',modify_audiostore='1',modify_moh='1',modify_tts='1',modify_contacts='1',modify_same_user_level='1',alter_admin_interface_options='1',modify_custom_dialplans='1',modify_colors='1',modify_dial_prefix='1' WHERE user='superadmin';"
mysql -u cron -p$DB_PASS asterisk -e "UPDATE asterisk.servers SET max_vicidial_trunks=150;"

# ---------------------------------------------------------
# 9. Apache Tuning
# ---------------------------------------------------------
sed -i 's/StartServers.*/StartServers 450/' /etc/apache2/server-tuning.conf
sed -i 's/MinSpareServers.*/MinSpareServers 250/' /etc/apache2/server-tuning.conf
sed -i 's/MaxSpareServers.*/MaxSpareServers 500/' /etc/apache2/server-tuning.conf
sed -i 's/ServerLimit.*/ServerLimit 768/' /etc/apache2/server-tuning.conf
sed -i 's/MaxClients.*/MaxClients 512/' /etc/apache2/server-tuning.conf
sed -i 's/MaxRequestsPerChild.*/MaxRequestsPerChild 100000/' /etc/apache2/server-tuning.conf

# ---------------------------------------------------------
# 10. Fail2Ban & Crontabs
# ---------------------------------------------------------
zypper install -y fail2ban
systemctl enable --now fail2ban
mv /etc/fail2ban/jail.local /etc/fail2ban/jail.bkp
asterisk -rx "module load codec_g729.so"

(crontab -l 2>/dev/null; echo "@reboot /usr/bin/VB-firewall --white --dynamic --quiet") | crontab -
(crontab -l 2>/dev/null; echo "* * * * * /usr/bin/VB-firewall --white --dynamic --quiet") | crontab -
systemctl restart cron

# ---------------------------------------------------------
# 11. Dynamic Portal Setup
# ---------------------------------------------------------
sed -i '1i Listen 81' /etc/apache2/listen.conf

sed -i "/^[[:space:]]*Listen[[:space:]]*443[[:space:]]*$/a \                Listen $DYNAMIC_PORT" /etc/apache2/listen.conf
sed -i "s/_default_:446/_default_:$DYNAMIC_PORT/g" /etc/apache2/vhosts.d/dynportal-ssl.conf

sed -i \
-e "s/\$PORTAL_userlevel=5;/\$PORTAL_userlevel=1;/" \
-e "s/\$PORTAL_topbar=1;/\$PORTAL_topbar=0;/" \
-e "s|\$PORTAL_redirecturl='X';|\$PORTAL_redirecturl='https://$DOMAIN/vicidial/welcome.php';|" \
-e "s/\$PORTAL_redirectlogin=1;/\$PORTAL_redirectlogin=0;/" \
/srv/www/vhosts/dynportal/inc/defaults.inc.php

systemctl restart apache2
systemctl enable apache2
systemctl enable asterisk
systemctl restart asterisk

# ---------------------------------------------------------
# 12. Firewall Final Rules
# ---------------------------------------------------------
firewall-cmd --zone=public --change-interface=eth0 --permanent
firewall-cmd --permanent --zone=public --add-port=$DYNAMIC_PORT/tcp
firewall-cmd --permanent --zone=external --add-port=$DYNAMIC_PORT/tcp
firewall-cmd --zone=public --add-port=$SIP_PORT/udp --permanent
firewall-cmd --zone=public --add-port=$PJSIP_PORT/udp --permanent
firewall-cmd --zone=public --add-port=$PJSIP_PORT/tcp --permanent
firewall-cmd --zone=public --add-port=10000-20000/udp --permanent
firewall-cmd --zone=public --add-port=8088/tcp --permanent
firewall-cmd --zone=public --add-port=8089/tcp --permanent
firewall-cmd --zone=public --add-masquerade --permanent
firewall-cmd --zone=external --add-masquerade --permanent
firewall-cmd --zone=public --remove-service=asterisk --permanent
firewall-cmd --zone=public --remove-service=apache2 --permanent
firewall-cmd --zone=public --remove-service=apache2-ssl --permanent
firewall-cmd --reload

# ---------------------------------------------------------
# 13. DAHDI & Branding
# ---------------------------------------------------------
modprobe dahdi
modprobe dahdi_dummy
dahdi_cfg -vv
systemctl enable --now dahdi
asterisk -rx "module load app_confbridge.so"

cd /root
git clone https://github.com/myleadsdialer/dialer.git
cp -f dialer/jail.local /etc/fail2ban/
sudo chown root:root /etc/fail2ban/jail.local
sudo chmod 644 /etc/fail2ban/jail.local

# Images
cp -f dialer/vicidial_admin_web_logo.png /srv/www/htdocs/agc/images/
cp -f dialer/vicidial_admin_web_logo.png /srv/www/htdocs/vicidial/images/
cp -f dialer/vicidial_admin_web_logoSAMPLE.png /srv/www/htdocs/vicidial/images/
cp -f dialer/vicidial_admin_web_logoDEFAULTAGENT.png /srv/www/htdocs/vicidial/images/
cp -f dialer/vicidial_admin_web_logo.gif /srv/www/htdocs/vicidial/images/
cp -f dialer/vicidial_admin_web_logo_small.gif /srv/www/htdocs/vicidial/images/

chmod -R +rwx /srv/www/htdocs/agc/images/
chmod -R +rwx /srv/www/htdocs/vicidial/images/
chmod -R +rwx /srv/www/htdocs/vicidial/
chmod 644 /srv/www/htdocs/agc/images/vicidial_admin_web_logo*
chmod 644 /srv/www/htdocs/vicidial/images/vicidial_admin_web_logo*
chown wwwrun:www /srv/www/htdocs/vicidial/images/vicidial_admin_web_logo*

echo "--- Setup for $DOMAIN complete! ---"
echo "Superadmin password has been set. Reboot recommended."

#!/bin/bash
# Подготовка зависимостей
yum -y update
yum -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
yum -y install https://rpms.remirepo.net/enterprise/remi-release-7.rpm
yum -y install yum-utils
yum-config-manager --disable 'remi-php*'
yum-config-manager --enable remi-php80
yum install wget
# Добавляем репозиторий MariaDB
touch /etc/yum.repos.d/mariadb.repo
echo '# MariaDB 10.6 CentOS repository list - created 2023-05-27 06:09 UTC'  >>/etc/yum.repos.d/mariadb.repo
echo '# https://mariadb.org/download/'  >>/etc/yum.repos.d/mariadb.repo
echo '[mariadb]' >>/etc/yum.repos.d/mariadb.repo
echo 'name = MariaDB' >>/etc/yum.repos.d/mariadb.repo
echo '# rpm.mariadb.org is a dynamic mirror if your preferred mirror goes offline. See https://mariadb.org/mirrorbits/ for details.' >>/etc/yum.repos.d/mariadb.repo
echo '# baseurl = https://rpm.mariadb.org/10.6/centos/$releasever/$basearch' >>/etc/yum.repos.d/mariadb.repo
echo 'baseurl = https://mirrors.xtom.de/mariadb/yum/10.6/centos/$releasever/$basearch' >>/etc/yum.repos.d/mariadb.repo
echo 'module_hotfixes = 1' >>/etc/yum.repos.d/mariadb.repo
echo '# gpgkey = https://rpm.mariadb.org/RPM-GPG-KEY-MariaDB' >>/etc/yum.repos.d/mariadb.repo
echo 'gpgkey = https://mirrors.xtom.de/mariadb/yum/RPM-GPG-KEY-MariaDB' >>/etc/yum.repos.d/mariadb.repo
echo 'gpgcheck = 1' >>/etc/yum.repos.d/mariadb.repo

# Установка зависимостей
yum -y install httpd curl mariadb-server mariadb-client php php-cli php-common php-gd php-mbstring php-mysqlnd php-pdo php-xml php-zip php-tokenizer php-json php-curl php-openssl php-zlib php-bcmath php-posix
# Firewall настройка
firewall-cmd --add-service=http --permanent
firewall-cmd --add-service=https --permanent 
firewall-cmd --reload
# Создание базы данных и пользователя для Pterodactyl
systemctl start mariadb
systemctl enable mariadb
mysql -u root -e "CREATE DATABASE panel;"
read -s -p "Введите пароль для базы данных (Стандартный 6482):" PASS
if [ -z "$PASS" ]; then
# Если переменная pass не определена, устанавливаем стандартное значение
PASS="6482"
fi
read -s -p "Введите домен который будет использовать панель (Позже нужно будет повторно написать только уже http://domain.com):" DOMAIN
mysql -u root -e "CREATE USER 'pterodactyl'@'127.0.0.1' IDENTIFIED BY '$PASS';"
mysql -u root -e "GRANT ALL PRIVILEGES ON panel.* TO 'pterodactyl'@'127.0.0.1' WITH GRANT OPTION;" 
# Установка Composer
curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
# Скачивание и установка Pterodactyl
mkdir -p /var/www/pterodactyl
cd /var/www/pterodactyl
curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
tar -xzvf panel.tar.gz
chmod -R 755 storage/* bootstrap/cache
cp .env.example .env
composer install --no-dev --optimize-autoloader
php artisan key:generate --force
# Настройка конфигурации и добавление данных в БД (это настроить не получиться через скрипт).
php artisan p:environment:setup
php artisan p:environment:database
php artisan migrate --seed --force
php artisan p:user:make
# Настройка веб-сервера
chown -R apache:apache /var/www/pterodactyl/*
systemctl start httpd
systemctl enable httpd
touch /etc/httpd/conf.d/pterodactyl.conf
echo '<VirtualHost *:80>'  >> /etc/httpd/conf.d/pterodactyl.conf
echo  'ServerName $DOMAIN' >> /etc/httpd/conf.d/pterodactyl.conf
echo  DocumentRoot "/var/www/pterodactyl/public" >> /etc/httpd/conf.d/pterodactyl.conf
echo   AllowEncodedSlashes On >> /etc/httpd/conf.d/pterodactyl.conf
echo   php_value upload_max_filesize 100M >> /etc/httpd/conf.d/pterodactyl.conf
echo   php_value post_max_size 100M >> /etc/httpd/conf.d/pterodactyl.conf
echo   '<Directory "/var/www/pterodactyl/public">' >> /etc/httpd/conf.d/pterodactyl.conf
echo     AllowOverride all >> /etc/httpd/conf.d/pterodactyl.conf
echo     Require all granted >> /etc/httpd/conf.d/pterodactyl.conf
echo   '</Directory>'  >> /etc/httpd/conf.d/pterodactyl.conf
echo '</VirtualHost>' >> /etc/httpd/conf.d/pterodactyl.conf
#Настройка CRON задачи
echo * * * * * php /var/www/pterodactyl/artisan schedule:run >> /etc/crontab
# Добавления сервиса для панели и настройка автозапуска
touch /etc/systemd/system/pteroq.service
echo '# Pterodactyl Queue Worker File ' >> /etc/systemd/system/pteroq.service
echo '# ---------------------------------- ' >> /etc/systemd/system/pteroq.service
echo [Unit]  >> /etc/systemd/system/pteroq.service 
echo Description=Pterodactyl Queue Worker  >> /etc/systemd/system/pteroq.service
echo '#After=redis-server.service'  >> /etc/systemd/system/pteroq.service
echo [Service]  >> /etc/systemd/system/pteroq.service
echo '# On some systems the user and group might be different.' >> /etc/systemd/system/pteroq.service
echo '# Some systems use `apache` or `nginx` as the user and group.' >> /etc/systemd/system/pteroq.service
echo User=apache >> /etc/systemd/system/pteroq.service
echo Group=apache >> /etc/systemd/system/pteroq.service
echo Restart=always >> /etc/systemd/system/pteroq.service
echo ExecStart=/usr/bin/php /var/www/pterodactyl/artisan queue:work --queue=high,standard,low --sleep=3 --tries=3 >> /etc/systemd/system/pteroq.service
echo StartLimitInterval=180 >> /etc/systemd/system/pteroq.service
echo StartLimitBurst=30 >> /etc/systemd/system/pteroq.service
echo RestartSec=5s >> /etc/systemd/system/pteroq.service
echo [Install] >> /etc/systemd/system/pteroq.service
echo WantedBy=multi-user.target >> /etc/systemd/system/pteroq.service
systemctl enable --now pteroq.service
systemctl start pteroq.service
systemctl restart httpd

#!/bin/bash

# シェルから流す場合は、ルートユーザーになること!!!!

######################## 設定項目 #############################

# ルートページ（登録／ログインなど）ドメイン
rootDomain='top.instant.com'

# エディター用(Codiad)ドメイン
# ルートページ側で認証を行う場合は、
# セッションをクッキーで受け渡すために
# ドメイン部分をルートページと共通にしてください。
editorDomain="editor.instant.com"

# プレビュー用ドメイン
previewDomain="preview.instant.com"

# タイムゾーン
timezone='Asia/Tokyo'

# Codiad "base" ユーザーパスワード
basePassword='whitebase'

# ルートページ（登録／ログイン等）インストール
# /home/home/topがインストール先
rootSystemInstall() {
    git clone https://github.com/InstantLaravel/TopPage.git /home/home/top
    cd /home/home/top
    composer install
    cd
}

# ルートページドキュメントルート
rootPageDocRoot='public'

# 学習対象PHPシステムインストール
# /home/codiad/workspace/baseがインストール先
# インストールした全ディレクトリー／ファイルは、所有オーナーbase、所属グループcodiadにし、
# ディレクトリーは、gidのセットを上位ディレクトリーから継承している
learningTargetInstall() {
    # 現在CodiadはUTF8のファイル保存時に正しく保存されないため英語オリジナル版をベースとして使用
    composer create-project laravel/laravel /home/codiad/workspace/base --prefer-dist

    # 日本語言語ファイルのみ日本語翻訳版からコピー
    wget https://github.com/laravel-ja/laravel/archive/master.zip
    unzip master.zip
    mv laravel-master/app/lang/ja /home/codiad/workspace/base/app/lang/ja
    rm -R laravel-master
    rm master.zip

    # Bootstrapをpublicへセット
    wget https://github.com/twbs/bootstrap/releases/download/v3.2.0/bootstrap-3.2.0-dist.zip
    unzip bootstrap-3.2.0-dist.zip -d bootstrap
    mv bootstrap/bootstrap-3.2.0-dist/* /home/codiad/workspace/base/public
    rm -R bootstrap*
}

# ルートページ（認証）とCodiad（エディター）の認証ブリッジスクリプトパス
# ルートページで認証せず、Codiadの認証を使用する場合は空白
#  =>その場合は、Codiadで認証を行う
authBridgeScript=''


######################## 設定終了 #############################

# ユーザー作成
useradd --home-dir /home/home --create-home --user-group home
useradd --home-dir /home/codiad --create-home --user-group codiad
useradd --home-dir /home/base --create-home --user-group base

# SSHログイン禁止
echo "- : home : ALL" >> /etc/security/access.conf
echo "- : codiad : ALL" >> /etc/security/access.conf
echo "- : preview : ALL" >> /etc/security/access.conf

# baseユーザーで作成したファイルをエディターで編集可能にする
echo "umask 002" >> /home/base/.profile

# 既存パッケージ更新
apt-get update
apt-get upgrade -y

# プライベートリポジトリ登録コマンドのインストール
apt-get install -y software-properties-common

# プライベートリポジトリの登録
apt-add-repository ppa:nginx/stable -y

# 以降のインストールに備えて、再度パッケージリストの更新
apt-get update

# 基本ツールのインストール
apt-get install -y vim unzip git

# タイムゾーン設定、-fオプションで既に存在するリンクと同名のファイルを削除
ln -sf /usr/share/zoneinfo/${timezone} /etc/localtime

# SQLiteインストール
# シンプルにするためするため、DBはSQLiteのみ
apt-get install -y sqlite3

# PHP関係のインストール
apt-get install -y php5-cli php5-dev \
    php5-json php5-curl php5-sqlite\
    php5-imap php5-mcrypt

php5enmod mcrypt pdo opcache json curl

# PHPコマンドライン設定
sed -i -e "s/error_reporting = .*/error_reporting = E_ALL/" \
    -e "s/display_errors = .*/display_errors = On/" \
    -e "s/memory_limit = .*/memory_limit = 300M/" \
    -e "s/;date.timezone.*/date.timezone = UTC/" /etc/php5/cli/php.ini

# Nginx、PHP-FPMインストール
# nginx-lightでも、今回の要件を満たしているはず
apt-get install -y nginx php5-fpm

# PHP-FPMオプション設定
sed -i -e "s/error_reporting = .*/error_reporting = E_ALL/" \
    -e "s/display_errors = .*/display_errors = On/" \
    -e "s/;cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/" \
    -e "s/memory_limit = .*/memory_limit = 300M/" \
    -e "s/;date.timezone.*/date.timezone = UTC/" /etc/php5/fpm/php.ini

# Nginxオプション設定
sed -i -e "s/user www-data;/user home;/" \
    -e "s/# server_names_hash_bucket_size.*/server_names_hash_bucket_size 64;/" /etc/nginx/nginx.conf

# PHP-FPM実行ユーザー変更
cp /etc/php5/fpm/pool.d/www.conf /etc/php5/fpm/pool.d/home.conf
cp /etc/php5/fpm/pool.d/www.conf /etc/php5/fpm/pool.d/codiad.conf
cp /etc/php5/fpm/pool.d/www.conf /etc/php5/fpm/pool.d/preview.conf
sed -i -e "s/user = www-data/user = home/" \
    -e "s/group = www-data/group = home/" \
    -e "s/\[www\]/[home]/" \
    -e "s@^listen = .*\$@listen = /var/run/php5-fpm.home.sock@" \
    -e "s/^;\?listen\.owner.*\$/listen.owner = home/" \
    -e "s/^;\?listen\.group.*\$/listen.group = home/" \
    -e "s/^;\?listen\.mode.*\$/listen.mode = 0666/" /etc/php5/fpm/pool.d/home.conf
sed -i -e "s/user = www-data/user = codiad/" \
    -e "s/group = www-data/group = codiad/" \
    -e "s/\[www\]/[codiad]/" \
    -e "s@^listen = .*\$@listen = /var/run/php5-fpm.codiad.sock@" \
    -e "s/^;\?listen\.owner.*\$/listen.owner = codiad/" \
    -e "s/^;\?listen\.group.*\$/listen.group = codiad/" \
    -e "s/^;\?listen\.mode.*\$/listen.mode = 0666/" /etc/php5/fpm/pool.d/codiad.conf
# previewには、禁止function設定、php.iniの値に追加される
sed -i -e "s/^user =.*\$/user = preview/" \
    -e "s/^group =.*\$/group = preview/" \
    -e "s/\[www\]/[preview]/" \
    -e "\$a php_admin_value[disable_functions] = dl,exec,passthru,shell_exec,system,proc_open,popen,curl_exec,curl_multi_exec,parse_ini_file,show_source\n" \
    -e "s@^listen = .*\$@listen = /var/run/php5-fpm.preview.sock@" \
    -e "s/^;\?listen\.owner.*\$/listen.owner = preview/" \
    -e "s/^;\?listen\.group.*\$/listen.group = preview/" \
    -e "s/^;\?listen\.mode.*\$/listen.mode = 0666/" /etc/php5/fpm/pool.d/preview.conf

# Composerインストール
curl -sS https://getcomposer.org/installer | php
mv composer.phar /usr/local/bin/composer

# ルートページインストール
# インストール先は/home/home/top
rootSystemInstall
# インストール終了後、オーナーを変更
chown -R home:codiad /home/home/top
# codiadグループから書き込めるようにする
find /home/home/top -type d -exec sudo chmod 2775 {} +
find /home/home/top -type f -exec sudo chmod 0664 {} +

# Codiadホームにgidをセットし、新規ディレクトリー／ファイルのグループが変わらないようにする
chown codiad:codiad /home/codiad
chmod g+s /home/codiad

# Codiadインストール
# (masterは不安定=>)git clone https://github.com/Codiad/Codiad.git /home/codiad
wget https://github.com/Codiad/Codiad/archive/v.2.2.8.zip
mkdir temp
unzip v.2.2.8.zip -d temp
cp -R temp/Codiad-v.2.2.8/* /home/codiad
rm v.2.2.8*
rm -R temp

# Codiad日本語化ファイルのインストール
git clone https://gist.github.com/b55af329ac844c985bf3.git temp
mv temp/ja.php /home/codiad/languages
rm -R temp
sed -i -e 's/"english",/"english",\n    "ja" => "日本語",/' /home/codiad/languages/code.php

# Codiad初期設定
echo "<?php/*|[\"\",{\"username\":\"base\",\"path\":\"base\",\"focused\":true}]|*/?>" > /home/codiad/data/active.php
chmod 664 /home/codiad/data/active.php
echo "<?php/*|[{\"name\":\"\u30a4\u30f3\u30b9\u30bf\u30f3\u30c8Laravel base\",\"path\":\"base\"}]|*/?>" > /home/codiad/data/projects.php
chmod 664 /home/codiad/data/projects.php
echo "<?php echo sha1(md5(\"${basePassword}\"));" > temp.php
hashedPassword=`php -f temp.php`
rm temp.php
echo "<?php/*|[{\"username\":\"base\",\"password\":\"${hashedPassword}\",\"project\":\"base\"}]|*/?>" > /home/codiad/data/users.php
chmod 664 /home/codiad/data/users.php
if [ -n "${authBridgeScript}" ]
then
    # ブリッジスクリプト登録
    sed -i -e "s+//define(\"AUTH_PATH\", \"\");+define(\"AUTH_PATH\", \"${authBridgeScript}\");+" /home/codiad/config.example.php
    # 非認証時はホームへリダイレクト
    sed -i -e "s+// Login form+// 未認証時はルート（認証）ページヘ移動\n    header(\"Location: http://${rootDomain}\"); die();+" /home/codiad/index.php
fi
sed -e "s+/path/to/codiad+/home/codiad+" \
       -e "s+domain\.tld+${editorDomain}+" \
       -e "s+America/Chicago+${timezone}+" /home/codiad/config.example.php > /home/codiad/config.php
chown -R codiad:codiad /home/codiad
chmod 775 /home/codiad/data
chmod 775 /home/codiad/workspace

# 学習対象プロジェクトインストール
# インストール先は、/home/codiad/workspace/base
learningTargetInstall
# インストール終了後、オーナーを変更
chown -R base:codiad /home/codiad/workspace/base
# codiadグループから書き込めるようにする
find /home/codiad/workspace/base -type d -exec sudo chmod 2775 {} +
find /home/codiad/workspace/base -type f -exec sudo chmod 0664 {} +

# Nginxデフォルト設定ファイルを書き換え
cat <<EOT > /etc/nginx/sites-available/default
server {
        listen 80 ;
        server_name ${rootDomain};

        root /home/home/top/${rootPageDocRoot};

        index index.php;

        location / {
                try_files \$uri \$uri/ /index.php?\$query_string;
                location ~ \\.php$ {
                        include fastcgi_params;
                        # SCRIPT_FILENAMEをオーバーライト
                        fastcgi_param SCRIPT_FILENAME  \$document_root\$fastcgi_script_name;
                        fastcgi_split_path_info ^(.+\\.php)(/.+)$;
                        fastcgi_pass unix:/var/run/php5-fpm.home.sock;
                        fastcgi_index index.php;
                }
        }

        location = favicon.ico { access_log off; log_not_found off; }
        location = robots.txt { access_log off; log_not_found off; }

        access_log off;
        error_log /var/log/nginx/error.log error;
#       rewrite_log on;

        error_page 404 /index.php;

        sendfile off;
}
EOT
cat <<EOT > /etc/nginx/sites-available/editor
server {
        listen 80;
        server_name ${editorDomain};

        root /home/codiad;

        index index.php;

        location / {
                try_files \$uri \$uri/ /index.php?\$query_string;
                location ~ \\.php$ {
                        include fastcgi_params;
                        # SCRIPT_FILENAMEをオーバーライト
                        fastcgi_param SCRIPT_FILENAME  \$document_root\$fastcgi_script_name;
                        fastcgi_split_path_info ^(.+\\.php)(/.+)$;
                        fastcgi_pass unix:/var/run/php5-fpm.codiad.sock;
                        fastcgi_index index.php;
                }
        }

        location = favicon.ico { access_log off; log_not_found off; }
        location = robots.txt { access_log off; log_not_found off; }

        location ~ ^/workspace {
            return 404;
            break;
        }

        access_log off;
        error_log /var/log/nginx/error.log error;
#       rewrite_log on;

        error_page 404 /404.html;
        error_page 500 502 503 504;
        location = /50x.html {
                root /usr/share/nginx/www;
        }

        sendfile off;
}
EOT
cat <<EOT > /etc/nginx/sites-available/preview
server {
        listen 80;
        server_name ${previewDomain};

        root /home/codiad/workspace;

        index index.html index.php;

        location ~ / {
                try_files \$uri \$uri/ /index.php\?$query_string;
                location ~ \\.php$ {
                        include fastcgi_params;
                        # SCRIPT_FILENAMEをオーバーライト
                        fastcgi_param SCRIPT_FILENAME  \$document_root\$fastcgi_script_name;
                        fastcgi_split_path_info ^(.+\\.php)(/.+)$;
                        fastcgi_pass unix:/var/run/php5-fpm.preview.sock;
                        fastcgi_index index.php;
                }
        }

        location = favicon.ico { access_log off; log_not_found off; }
        location = robots.txt { access_log off; log_not_found off; }

        access_log off;
        error_log /var/log/nginx/error.log error;
#       rewrite_log on;

        error_page 404 /index.php;

        sendfile off;
}
EOT

# 仮想ホストを有効にする
ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled
ln -s /etc/nginx/sites-available/editor /etc/nginx/sites-enabled
ln -s /etc/nginx/sites-available/preview /etc/nginx/sites-enabled

# Nginx、php5-fpm再起動
service nginx restart
service php5-fpm restart


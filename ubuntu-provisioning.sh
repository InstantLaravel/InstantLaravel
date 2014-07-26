#!/bin/bash


# シェルから流す場合は、ルートユーザーになること!!!!



######################## 設定項目 #############################



# ルートページ（登録／ログインなど）ドメイン
rootDomain='top.instant.com'
# ルートページドキュメントルート
rootPageDocRoot='public'


# エディター用(Codiad)ドメイン
editorDomain="editor.instant.com"


# プレビュードメイン名
previewDomain='check.instant.com'
# プレビュー用ドキュメントルート
previewDocRoot='public'

# タイムゾーン
timezone='Asia/Tokyo'


# Codiad "base" ユーザーパスワード
basePassword='whitebase'



######################## 設定終了 #############################



#######################
# ユーザー関係・基本設定 #
#######################

# ユーザー作成
useradd --home-dir /home/home --create-home --user-group home
useradd --home-dir /home/codiad --create-home --user-group codiad
useradd --home-dir /home/base --create-home --user-group base


# SSHログイン禁止
echo "- : home : ALL" >> /etc/security/access.conf
echo "- : codiad : ALL" >> /etc/security/access.conf
echo "- : base : ALL" >> /etc/security/access.conf


# homeとbaseユーザーで作成したファイルをエディターで編集可能にする
echo "umask 002" >> /home/base/.profile
echo "umask 002" >> /home/home/.profile


# タイムゾーン設定、-fオプションで既に存在するリンクと同名のファイルを削除
ln -sf /usr/share/zoneinfo/${timezone} /etc/localtime


#############
# パッケージ #
#############

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


# SQLiteインストール
# シンプルにするためするため、DBはSQLiteのみ
apt-get install -y sqlite3


##################
# PHP、Nginx設定 #
##################


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


# PHP-FPM PHPオプション設定
sed -i -e "s/error_reporting = .*/error_reporting = E_ALL/" \
    -e "s/display_errors = .*/display_errors = On/" \
    -e "s/;cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/" \
    -e "s/memory_limit = .*/memory_limit = 300M/" \
    -e "s/;date.timezone.*/date.timezone = UTC/" /etc/php5/fpm/php.ini


# Nginxオプション設定
sed -i -e "s/user www-data;/user www-data;/" \
    -e "s/keepalive_timeout .*/keepalive_timeout 30/" \
    -e "s/^worker_processes .*/worker_processes auto;/" \
    -e "s/# server_names_hash_bucket_size .*/server_names_hash_bucket_size 64;/" /etc/nginx/nginx.conf


# PHP-FPM設定

# ホーム（新規登録）
# 一時にアクセスが集まり、その他の時間はほどほどの予想
cat <<EOT > /etc/php5/fpm/pool.d/home.conf
[home]
user = home
group = home
listen = /var/run/php5-fpm.home.sock
listen.owner = home
listen.group = www-data
listen.mode = 0660
pm = ondemand
pm.max_children = 10
pm.start_servers = 2
pm.min_spare_servers = 2
pm.max_spare_servers = 6
chdir = /
EOT

# エディター(Codiad)
# 小さな量のアクセスが、チュートリアル中持続する
cat <<EOT > /etc/php5/fpm/pool.d/codiad.conf
[codiad]
user = codiad
group = codiad
listen = /var/run/php5-fpm.codiad.sock
listen.owner = codiad
listen.group = www-data
listen.mode = 0660
pm = dynamic
pm.max_children = 8
pm.start_servers = 3
pm.min_spare_servers = 3
pm.max_spare_servers = 5
chdir = /
EOT

# baseユーザー（管理ユーザー）
# 専用プレビュー
cat <<EOT > /etc/php5/fpm/pool.d/base.conf
[base]
user = base
group = base
listen = /var/run/php5-fpm.base.sock
listen.owner = base
listen.group = www-data
listen.mode = 0660
pm = ondemand
pm.max_children = 2
pm.start_servers = 2
pm.min_spare_servers = 1
pm.max_spare_servers = 2
chdir = /
EOT


# Nginx 仮想ホスト設定


# トップ（認証／ログイン）仮想ホスト設定
cat <<EOT > /etc/nginx/sites-available/default
server {
    listen 80 default_server;
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

    error_log /var/log/nginx/error.log error;
#    rewrite_log on;

    sendfile off;
}
EOT


# エディター仮想ホスト設定
cat <<EOT > /etc/nginx/sites-available/editor
server {
    listen 80;
    server_name ${editorDomain};

    root /home/codiad;

    location / {
        try_files \$uri /index.php?\$query_string;
        location ~ \\.php$ {
            include fastcgi_params;
            # SCRIPT_FILENAMEをオーバーライト
            fastcgi_param SCRIPT_FILENAME  \$document_root\$fastcgi_script_name;
            fastcgi_split_path_info ^(.+\\.php)(/.+)$;
            fastcgi_pass unix:/var/run/php5-fpm.codiad.sock;
            fastcgi_index index.php;
        }
    }

    # 直接codiaユーザーでアクセスさせると、workspace下の
    # ファイルは全部変更できるため、拒否する。
    location ~ ^/workspace {
        return 403;
    }

    error_log /var/log/nginx/error.log error;
#    rewrite_log on;

    sendfile off;
}
EOT

# プレビュー仮想ホスト設定
cat <<EOT > /etc/nginx/sites-available/preview
server {
    listen 80;
    server_name ${previewDomain};

    root /home/codiad/workspace;

    location / {
        try_files \$uri /index.html;
    }

    location ^~ /(css|js|img|fonts)/ {
        access_log off;
        try_files \$uri \404.html;
    }

    # このドメインのトップレベルではPHPを実行させない
    # そのため、fastcgiへのブリッジ処理は記述しない

    # 末尾のスラッシュ除去
    rewrite ^/(.+)/$ /\$1;

    include /etc/nginx/users.d/*;

    error_log /var/log/nginx/error.log error;
#   rewrite_log on;

    sendfile off;
}
EOT


# 仮想ホストを有効にする
ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled
ln -s /etc/nginx/sites-available/editor /etc/nginx/sites-enabled
ln -s /etc/nginx/sites-available/preview /etc/nginx/sites-enabled


# 各ユーザー用の設定フォルダーを作成する
mkdir /etc/nginx/users.d


# baseユーザー用設定ファイル
cat <<EOT > /etc/nginx/users.d/base
    location ~ ^/base(/(.+))?$ {
        root /home/codiad/workspace/base/public;

        try_files \$1 /base/index.php?\$query_string;

        location ~ ^/base/index.php$ {
            include fastcgi_params;
            # パラメーターをオーバーライト
            fastcgi_param SCRIPT_FILENAME /home/codiad/workspace/base/public/index.php;
            fastcgi_split_path_info ^(.+\\.php)(.+)$;
            fastcgi_pass unix:/var/run/php5-fpm.base.sock;
            fastcgi_index index.php;
        }
    }
EOT


###############
# ルートページ #
###############


# Composerインストール
curl -sS https://getcomposer.org/installer | php
mv composer.phar /usr/local/bin/composer


# ルートページインストール
# インストール先は/home/home/top
git clone https://github.com/InstantLaravel/TopPage.git /home/home/top
cd /home/home/top
composer install
cd


# インストール終了後、オーナーを変更
chown -R home:codiad /home/home/top


# codiadグループから書き込めるようにする
find /home/home/top -type d -exec chmod 2775 {} +
find /home/home/top -type f -exec chmod 0664 {} +


# 新規ユーザー作成シェルをsuduで実行するための準備
chmod 744 /home/home/top/add-new-user.sh
echo "home ALL=(ALL) NOPASSWD: /home/home/top/add-new-user.sh" > /etc/sudoers.d/home
echo "home ALL=(ALL) NOPASSWD: /usr/sbin/service" >> /etc/sudoers.d/home
echo 'Defaults:home !requiretty' >> /etc/sudoers.d/home


# ルートロジック中のリダイレクト先設定

sed -i -e "s/\*\*\* EDITOR DOMAIN \*\*\*/${editorDomain}/" /home/home/top/app/routes.php


##############
# Codiad関係 #
##############


# Codiadホームにgidをセットし、新規ディレクトリー／ファイルのグループが変わらないようにする
chown codiad:codiad /home/codiad
chmod g+s /home/codiad


# Codiadインストール
# wget https://github.com/Codiad/Codiad/archive/v.2.2.8.zip
wget https://github.com/Codiad/Codiad/archive/master.zip
mkdir temp
unzip master.zip -d temp
cp -R temp/Codiad-master/* /home/codiad
rm master.zip
rm -R temp


# Codiad日本語化ファイルのインストール
git clone https://gist.github.com/b55af329ac844c985bf3.git temp
mv temp/ja.php /home/codiad/languages
rm -R temp
sed -i -e 's/"english",/"english",\n    "ja" => "日本語",/' /home/codiad/languages/code.php


# Codiad初期設定
#echo "<?php/*|[\"\",{\"username\":\"base\",\"path\":\"base\",\"focused\":true}]|*/?>" > /home/codiad/data/active.php
echo "<?php/*|[\"\"]|*/?>" > /home/codiad/data/active.php
echo "<?php/*|[{\"name\":\"\u30a4\u30f3\u30b9\u30bf\u30f3\u30c8Laravel base\",\"path\":\"base\"}]|*/?>" > /home/codiad/data/projects.php
echo "<?php echo sha1(md5(\"${basePassword}\"));" > temp.php
hashedPassword=`php -f temp.php`
rm temp.php
echo "<?php/*|[{\"username\":\"base\",\"password\":\"${hashedPassword}\",\"project\":\"base\"}]|*/?>" > /home/codiad/data/users.php
sed -e "s+/path/to/codiad+/home/codiad+" \
       -e "s+domain\.tld+${editorDomain}+" \
       -e "s+America/Chicago+${timezone}+" /home/codiad/config.example.php > /home/codiad/config.php
chown -R codiad:codiad /home/codiad
chown home:codiad /home/codiad/data
chown home:codiad /home/codiad/data/*.php
chmod 775 /home/codiad/data
chmod 775 /home/codiad/workspace
chmod 664 /home/codiad/data/*.php


######################
# チュートリアル対象FW #
######################


# 学習対象プロジェクトインストール
# インストール先は、/home/codiad/workspace/base
# 現在CodiadはUTF8のファイル保存時に正しく保存されないため英語オリジナル版をベースとして使用
composer create-project laravel/laravel /home/codiad/workspace/base


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


# インストール終了後、オーナーを変更
chown -R base:codiad /home/codiad/workspace/base


# codiadグループから書き込めるようにする
find /home/codiad/workspace/base -type d -exec sudo chmod 2775 {} +
find /home/codiad/workspace/base -type f -exec sudo chmod 0664 {} +


#############
# 固定ページ #
#############


# プレビューindexページ
sed -e "s/\*\*\* PREVIEW DOMAIN \*\*\*/${previewDomain}/" /home/home/top/preview-resources/index.html > /home/codiad/workspace/index.html


# プレビュー404ページ
mv /home/home/top/preview-resources/404.html /home/codiad/workspace/


# baseへレイアウトのサンプルを用意
mv /home/home/top/preview-resources/*.blade.php /home/codiad/workspace/base/app/views/


#################################################
# レビューのルートURLアクセス時のindex.htm用リソース #
#################################################


cp -R /home/home/top/public/css /home/codiad/workspace/
cp -R /home/home/top/public/js /home/codiad/workspace/
cp -R /home/home/top/public/fonts /home/codiad/workspace/
cp -R /home/home/top/public/img /home/codiad/workspace/


########################
# Nginx、php5-fpm再起動 #
########################


service nginx restart
service php5-fpm stop
service php5-fpm start



########################################
# Nginx、php5-fpm再起動要求監視シェル起動 #
########################################


chown root:root /home/home/top/restart-watchdoc.sh
chmod 744 /home/home/top/restart-watchdoc.sh
/home/home/top/restart-watchdoc.sh &


# 再起動時にも動作するようにrc.localへ登録
sed -i -e "s@^exit 0\$@/home/home/top/restart-watchdoc.sh \&> /dev/null\ \&\nexit 0@" /etc/rc.local
chmod 744 /etc/rc.local

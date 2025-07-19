#!/bin/bash

set -eox pipefail # verbose output, should also stop script if something fails

if [ "$1" = "-h" ]; then
	echo "Usage information for pull-production.sh:"
	echo ""
	echo "Development environment update script for syncing database and files from"
	echo "production to local development environment."
	echo ""
	echo "Depends on rsync and production ssh key and ssh connection setup"
    echo "and public_html path aliased to script directory."
    echo ""
    echo "Syntax:"
    echo ""
    echo "pull-production.sh"
    echo "pull-production.sh -h # prints this message"
	exit 1
fi

PROD_SSH_HOST=site1-server
PROD_WWW_PATH=/home/master/site1-production_kvuyvwheek/public_html
PROD_DOMAIN=site1.fi

DEV_DOMAIN=site1.test
VVV_SITE=site1
VVV_WWW_PATH=/srv/www/site1/public_html

# Change cwd to this script file's path

cd $(dirname "$0")

# Check if path ./public_html

if [ -d "./public_html" ]; then
	echo "Found ./public_html assuming it as WP www-root."
	LOCAL_WWW_PATH=./public_html
else
	echo "Error: WP www-root not found, something is off with the vvv dev environment"
	exit 1
fi

echo "cd'ing to local WP www-root"
cd $LOCAL_WWW_PATH

echo "Downloading PROD wp-content files, deleting local files that don't exist on PROD"

# --delete cleans target from files missing from source, eg. .git will be overwritten
rsync -av --progress --delete $PROD_SSH_HOST:$PROD_WWW_PATH/wp-content . --exclude 'object-cache.php' --exclude 'debug.log' --exclude 'plugins/site1-plugin' --exclude 'plugins/twig-templating-block'
# --exclude 'uploads' --exclude 'object-cache.php' --exclude 'mu-plugins/'  # these may be useful some times

echo 'Exporting PROD database'
ssh $PROD_SSH_HOST "cd $PROD_WWW_PATH && wp db export ~/wpdb.sql && cat ~/wpdb.sql | gzip > ~/wpdb.sql.gz && rm ~/wpdb.sql"

echo 'Downloading database export'
# --remove-source-files removes the wpdb.sql.gz from source after copy to keep things clean
rsync -av --progress --remove-source-files $PROD_SSH_HOST:~/wpdb.sql.gz .
gzip -d -f wpdb.sql.gz

# Check if ./public_html/wp-config.php exists, and try create if not
if [ ! -f "wp-config.php" ]
then
	echo "Error: wp-config.php not found, something is off with the vvv dev environment"
	echo "create with eg:"
	echo	'vagrant ssh -c "cd $VVV_WWW_PATH && wp config create --dbname=$VVV_SITE --dbuser=wp --dbpass=wp"'
	echo "Trying..."

	vagrant ssh -c "cd $VVV_WWW_PATH && wp config create --dbname=$VVV_SITE --dbuser=wp --dbpass=wp"
fi

echo "Importing database into vagrant box"

vagrant ssh -c "wp --path=$VVV_WWW_PATH db drop --yes"
vagrant ssh -c "wp --path=$VVV_WWW_PATH db create"
vagrant ssh -c "wp --path=$VVV_WWW_PATH db import $VVV_WWW_PATH/wpdb.sql"

echo "Running search & replace, deactivating PROD-only plugins etc."



vagrant ssh -c "wp --path=$VVV_WWW_PATH search-replace "//$PROD_DOMAIN" "//$DEV_DOMAIN" --skip-plugins"

## vagrant ssh -c "wp --path=$VVV_WWW_PATH search-replace \"https://\" \"http://\" --dry-run"  # comment this to use https

vagrant ssh -c "wp --path=$VVV_WWW_PATH option update admin_email "dev-email@flywheel.test" --skip-plugins"
vagrant ssh -c "wp --path=$VVV_WWW_PATH cache flush --skip-plugins"
# vagrant ssh -c "wp --path=$VVV_WWW_PATH plugin deactivate google-calendar-events --skip-plugins"
vagrant ssh -c "wp --path=$VVV_WWW_PATH user create admin admin@example.com --role=administrator --user_pass=password --skip-plugins && wp --path=$VVV_WWW_PATH user meta update admin locale en_US"

vagrant ssh -c "wp --path=$VVV_WWW_PATH transient delete --network woocommerce_blocks_patterns" # https://github.com/woocommerce/woocommerce/issues/53345 fixes in 9.9.0
echo "Sync complete, access via http://$DEV_DOMAIN"

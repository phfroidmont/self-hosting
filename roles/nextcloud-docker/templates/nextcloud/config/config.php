<?php
$CONFIG = array (
  'instanceid' => 'ocbsz7gnyjst',
  'passwordsalt' => '{{nextcloud_passwordsalt}}',
  'secret' => '{{nextcloud_secret}}',
  'trusted_domains' => 
  array (
    0 => 'localhost',
    2 => 'cloud.banditlair.com',
  ),
  'datadirectory' => '/var/www/html/data',
  'overwrite.cli.url' => 'https://cloud.banditlair.com',
  'dbtype' => 'mysql',
  'version' => '12.0.4.3',
  'dbname' => 'nextcloud',
  'dbhost' => 'db',
  'dbport' => '3306',
  'dbtableprefix' => 'oc_',
  'dbuser' => 'nextcloud',
  'dbpassword' => '{{nextcloud_mysql_password}}',
  'installed' => true,
  'memcache.local' => '\\OC\\Memcache\\APCu',
  'htaccess.RewriteBase' => '/',
  'apps_paths' => 
  array (
    0 => 
    array (
      'path' => '/var/www/html/apps',
      'url' => '/apps',
      'writable' => false,
    ),
    1 => 
    array (
      'path' => '/var/www/html/custom_apps',
      'url' => '/custom_apps',
      'writable' => true,
    ),
  ),
  'maintenance' => false,
  'updater.release.channel' => 'stable',
  'loglevel' => '1',
  'mail_smtpmode' => 'smtp',
  'mail_smtpauthtype' => 'LOGIN',
  'mail_smtpsecure' => 'ssl',
  'mail_smtpauth' => 1,
  'mail_from_address' => 'noreply',
  'mail_domain' => 'banditlair.com',
  'mail_smtphost' => 'mail.banditlair.com',
  'mail_smtpport' => '465',
  'mail_smtpname' => 'noreply@banditlair.com',
  'mail_smtppassword' => '{{email_password}}',
  'filelocking.enabled' => true,
);

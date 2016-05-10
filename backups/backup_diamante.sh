#!/bin/sh
# Name: Backup Diamante
# Backups: Version 0.1.0
# Date: 05-04-2016
# Author: BLG
# Description: Takes backup of Diamante site in domain root directory - Backs up filesystem. Checks for Wordpress database, backs up database if present. Saves backups in directory specified by config file.

### CONFIG FILE # TODO put these in a separate config file
# File structure root
server_home="/home/diamanv1"

domain_root="/home/diamanv1/public_html"

# Backups directory, relative to server home
backups_dir="/home/diamanv1/backups"

# Log location
log_dir="logs"

# Number of backups to save
i=2

# Email to send reports
email="bethany@diamantegraphix.com"

## END OF CONFIG FILE

site="diamantedesignsolutions"

# Log time backups started
hold="##### Backups started at $(date +'%Y-%m-%d %H:%M:%S') #####"
hold="$hold\nBackup location: $backups_dir/"

# If backups directory does not exist, create it
if [ ! -d "$backups_dir" ]; then
  error=$(mkdir "$backups_dir" 2>&1)
  if [ $? == 0 ]; then
    hold="$hold\nBackups directory $backups_dir/ created"
  else
    hold="$hold\n\n$error"
    hold="$hold\n\n# Backups failed at $(date +'%d/%m/%Y %H:%M:%S')"
    echo -e $hold | mail -s "Diamante Backup Failed on $(date +'%Y-%m-%d'): No Backup Directory" -S from="diamanv1_backups" "$email"
    exit 0
  fi
fi

today="$(date +'_%Y-%m-%d')"

# Create temporary log file
templog="$backups_dir/temp$(date +'%d%m%Y%H%M%S').log"
touch "$templog" 2>/dev/null
if [ $? == 0 ]; then
  echo -e $hold >> "$templog"
else
  echo "Backups $(date +'%Y-%m-%d'): Unable to create log file at $templog" | mail -s "Diamante Backup Warning on $(date +'%Y-%m-%d'): No Log File" -S from="diamanv1_backups" "$email"
fi 

# If log directory does not exist, create it
if [ ! -d "$backups_dir/$logs_dir" ]; then
  mkdir "$backups_dir/$logs_dir" 2>>"$templog"
  if [ $? == 0 ]; then 
    echo "$backups_dir/$logs_dir directory created" >> "$templog"
  else
    echo "Unable to create directory $logs_dir/ in $backups_dir/" >> "$templog"  
    errors=true
  fi    
fi

# Log file named by year
logfile="$backups_dir/$logs_dir/backups$(date +'_%Y').log"

# Add 1 to number to backups to save, starts deleting on line following number to save
i=$(($i+1))

# Get error messages from all commands in a pipeline
set -o pipefail

  # Log site name
  echo >> "$templog"
  echo "# $site #" >> "$templog"

  # Check if site directory exists
  if [ -d "$domain_root" ]; then
    echo "Filesyetem located: $domain_root" >> "$templog" 
  else
    echo "$site backup not completed; $domain_root not found" >> "$templog"
    errors=true
    continue
  fi

  # If backups folder for site does not exist, create it
  if [ ! -d "$backups_dir/$site" ]; then
    mkdir "$backups_dir/$site" 2>>"$templog"
    if [ $? == 0 ]; then 
      echo "$backups_dir/$site directory created" >> "$templog"
    else
      echo "Filesystem backup: FAILED; Unable to create directory $site/ in $backups_dir/" >> "$templog"  
      errors=true
      continue
    fi    
  fi

  # Move to directory containing site directory 
  pushd "$domain_root" 2>&1>/dev/null

  # Create gzipped tar archive of filesystem
  zipfile="$site$today.tar.gz"
  tar -zcf "$backups_dir/$site/$zipfile" wp-admin/ wp-content/ wp-includes/ favicon.ico google749bb1ccc9295d8c.html index.php php.ini wordfence-waf.php wp-activate.php wp-blog-header.php wp-comments-post.php wp-config-sample.php wp-config.php wp-cron.php wp-links-opml.php wp-load.php wp-login.php wp-mail.php wp-settings.php wp-signup.php wp-trackback.php xmlrpc.php 2>>"$templog"

  # Log results of directorty compression
  if [ $? == 0 ]; then
    echo "Filesystem backup created: $zipfile" >> "$templog"    
  else
    echo "Filesystem backup: FAILED" >> "$templog"   
    errors=true
    continue
  fi

  # Move back to initial directory
  popd 2>&1>/dev/null 

  # Delete all but 2 most recent file backups
  ls -tp $backups_dir/$site/$site*.tar.gz 2>>"$templog" | tail -n +$i | xargs -I {} rm {} 2>>"$templog"
  if [ $? != 0 ]; then
    echo "Error deleting outdated tar backups" >> "$templog"
  fi

  # Get database info for WordPress site
  wpconfig="$domain_root/${wp}wp-config.php"
  if [ -f "$wpconfig" ]; then

    # Get database credentials
    mysql_name=$(cut -d "'" -f4 <<< $(grep DB_NAME "$wpconfig"))
    mysql_user=$(cut -d "'" -f4 <<< $(grep DB_USER "$wpconfig"))
    mysql_pass=$(cut -d "'" -f4 <<< $(grep DB_PASSWORD "$wpconfig"))
    #mysql_host=$(cut -d "'" -f4 <<< $(grep DB_HOST "$wpconfig"))

    # Log name of database
    echo "Database located: $mysql_name" >> "$templog"

    # Database dump
    sqlfile="$site$today.sql.gz"
    mysqldump --user="$mysql_user" --password="$mysql_pass" --default-character-set=utf8 "$mysql_name" 2>>"$templog" | gzip > "$backups_dir/$site/$sqlfile" 2>>"$templog"

    # Log database dump results
    if [ $? == 0 ]; then
      echo "Database backup created: $sqlfile" >> "$templog"
    else
      echo "Database backup: FAILED" >> "$templog"
      errors=true
      continue
    fi  

    # delete all but 2 most recent database backups
    ls -tp $backups_dir/$site/$site*.sql.gz 2>>"$templog" | tail -n +$i | xargs -I {} rm {} 2>>"$templog"
    if [ $? != 0 ]; then
      echo "Error deleting outdated sql backups" >> "$templog"
    fi

  # Log error if config file not found for WordPress site
  else 
    echo "Config file wp-config.php not found for WordPress site" >> "$templog"
    errors=true
  fi

# If an error occurred, note that in the log and in subject of email notification
if [ $errors ]; then
  echo >> "$templog"
  echo "*** ERRORS OCCURRED DURING THIS BACKUP ***" >> "$templog"
  subject="Diamante Backup Completed with Errors on $(date +'%Y-%m-%d')"
else
  subject="Diamante Backup Completed on $(date +'%Y-%m-%d')"
fi

# Log time backups were completed
echo >> "$templog"
echo "# Backups completed at $(date +'%Y-%m-%d %H:%M:%S') #" >> "$templog"

# Email log for current backup
cat "$templog" | mail -s "$subject" -S from="diamanv1_backups" "$email"

# Copy temp log to log file
cat "$templog" >> "$logfile"
echo >> "$logfile"
echo >> "$logfile"

rm "$templog"

exit 0

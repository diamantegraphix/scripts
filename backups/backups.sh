#!/bin/sh
# site on same server
# backup saved on same server



# File structure root
server_home="/var/www/html"

# Backups directory, relative to server home
backups_dir="$server_home/backups"

# Full path and name of log file
logfile="$backups_dir/backup.log"

# Full path of file with list of sites to backup; format = [site],[full path to parent folder of site]
sites="x$backups_dir/sites.txt"

# Number if backups to save
i=2

today="$(date +'_%Y-%m-%d')"

# Create temporary log file
tmplog="$server_home/tmplog$(date +'%d%m%Y%H%M%S').log"
touch $tmplog

# Get error messages from all commands in a pipeline
set -o pipefail

# Log time backups started
echo "##### Backups started at $(date +'%Y-%m-%d %H:%M:%S') #####" >> "$tmplog"

# If backups directorys does not exist, create it
if [ ! -d "$backups_dir" ]; then
  mkdir "$backups_dir" 2>>"$tmplog"
  if [ $? == 0 ] ; then
    echo "Backups directory $backups_dir/ created" >> "$tmplog"
  else
    #echo "Error: could not create backups directory" >> "$tmplog"
    echo "Backups failed at $(date +'%d/%m/%Y %H:%M:%S') " >> "$tmplog"
    #cat $tmplog | mail -s "Backups failed: No backup directory" "bethany@diamantegraphix.com"
    rm $tmplog
    exit 0
  fi
fi

# If logfile does not exist, create it
if [ ! -f "$logfile" ]; then
  touch "$logfile" 2>>"$tmplog"
  if [ $? != 0 ]; then 
    errors=true
    echo "Unable to create log file" >> "$tmplog" 
  fi
fi

# Add 1 to number to backups to save, starts deleting on line following number to save
i=$(($i+1))

# Get sites name and path (parent of site directory) from file
while IFS="," read site path; do 

  # Remove trailing slash from site directory path
  if [ "${path: -1}" = "/" ]; then 
    path="${path%?}"
  fi

  echo >> "$tmplog"
  echo "# $site #" >> "$tmplog"

  # Check if site directory exists
  if [ -d "$path/$site" ]; then
    echo "Filesyetem located: $path" >> "$tmplog" 
  else
    echo "$site backup not completed; $path/$site not found" >> "$tmplog"
    errors=true
    continue
  fi

  # If backups folder for site does not exist, create it
  if [ ! -d "$backups_dir/$site" ]; then
    mkdir "$backups_dir/$site" 2>>"$tmplog"
    if [ $? == 0 ]; then 
      echo "$backups_dir/$site directory created" >> "$tmplog"
    else
      errors=true
      continue
    fi    
  fi

  # Move to directory containing site directory 
  pushd "$path" 2>&1>/dev/null

  # Create gzipped tar archive of filesystem
  zipfile="$backups_dir/$site/$site$today$(date +'%d%m%Y%H%M%S').tar.gz"
  tar -zcf "$zipfile" $site 2>>"$tmplog"

  # Log results of directorty compression
  if [ $? == 0 ]; then
    echo "Filesystem backup created: $zipfile" >> "$tmplog"    
  else
    echo "Filesystem backup: FAILED" >> "$tmplog"   
    errors=true
    continue
  fi

  # Move back to initial directory
  popd 2>&1>/dev/null 

  # Delete all but 2 most recent file backups
  #find $backups_dir/$site -maxdepth 1 -name "$site*\.tar\.gz" 2>>"$tmplog" | sort -r | tail -n +$i | xargs -I {} rm {} 2>>"$tmplog"
  #^doesn't work. Sorts by file name, not last modified

  ls -tp $backups_dir/$site/$site*.tar.gz 2>>"$tmplog" | tail -n +$i | xargs -I {} rm {} 2>>"$tmplog" # NOTE: * wildcard can't be in quotes

  # If error deleting old backups, log error
  if [ $? != 0 ]; then
    echo "Error deleting outdated tar backups" >> "$tmplog"
  fi

  # Check if site is wordpress site
  if [ -f "$path/$site/index.php" ]; then
    check=$(grep "/wp-blog-header.php" "$path/$site/index.php" | cut -d "'" -f2)

    # Check if the index.php file loads WordPress
    if [ -z "$check" ]; then
      # Not a WordPress site
      continue
    elif [ "$check" == '/wp-blog-header.php' ]; then
      # Active WordPress install is in site directory
      wp=""
    else
      # Active WordPress install is in subdirectory of site directory
      wp=$(cut -d "/" -f2 <<< "$check")
      wp="$wp/"
    fi
  else
    # Not a WordPress site
    continue
  fi

  # Get database info for WordPress site
  wpconfig="$path/$site/${wp}wp-config.php"
  if [ -f "$wpconfig" ]; then

    # Get database credentials
    mysql_name=$(cut -d "'" -f4 <<< $(grep DB_NAME "$wpconfig"))
    mysql_user=$(cut -d "'" -f4 <<< $(grep DB_USER "$wpconfig"))
    mysql_pass=$(cut -d "'" -f4 <<< $(grep DB_PASSWORD "$wpconfig"))
    #mysql_host=$(cut -d "'" -f4 <<< $(grep DB_HOST "$wpconfig"))

    # Log name of database
    echo "Database located: $mysql_name" >> "$tmplog"

    # Database dump
    sqlfile="$backups_dir/$site/$site$today$(date +'%d%m%Y%H%M%S').sql.gz"
    mysqldump --user="$mysql_user" --password="$mysql_pass" --default-character-set=utf8 "$mysql_name" 2>>"$tmplog" | gzip > "$sqlfile" 2>>"$tmplog"

    # Log database dump results
    if [ $? == 0 ]; then
      echo "Database backup created: $sqlfile" >> "$tmplog"
    else
      echo "Database backup: FAILED" >> "$tmplog"
      errors=true
      continue
    fi  

    # delete all but 2 most recent database backups
    #find $backups_dir/$site -maxdepth 1 -name "$site*\.sql\.gz" 2>>"$tmplog" | sort -r | tail -n +3 | xargs -I {} rm {} 2>>"$tmplog"
    #^doesn't work. Sorts by file name, not last modified

    ls -tp $backups_dir/$site/$site*.sql.gz 2>>"$tmplog" | tail -n +$i | xargs -I {} rm {} 2>>"$tmplog" # NOTE: * wildcard can't be in quotes

    # If error deleting old database dumps, log error
    if [ $? != 0 ]; then
      echo "Error deleting outdated sql backups" >> "$tmplog"
    fi

  # Log error if config file not found for WordPress site
  else 
    echo "Config file wp-config.php not found for WordPress site" >> "$tmplog"
    errors=true
  fi
done < "$sites" 2>> "$tmplog"


# If file with list of sites does not exist, end program and email error message
if [ $? != 0 ]; then
  echo "Error: File not found: $sites" >> "$tmplog"
  echo "# Backups failed at $(date +'%d/%m/%Y %H:%M:%S') #" >> "$tmplog"
  cat "$tmplog" ###| mail -s "Backups failed: No site list file" "bethany@diamantegraphix.com"
  cat "$tmplog" >> "$logfile"
  #rm "$tmplog"
  exit 0
fi

# If an error occurred, note that in the log
if [ $errors ]; then
  echo >> "$tmplog"
  echo "*** ERRORS OCCURRED DURING THIS BACKUP ***" >> "$tmplog"
  echo >> "$tmplog"
  subject="ERRORS OCCURRED: Backups complete on $(date +'%Y-%m-%d)"
else
  subject="Backups complete on $(date +'%Y-%m-%d)"
fi

# Log time backups were completed
echo "# Backups completed at $(date +'%Y-%m-%d %H:%M:%S') #" >> "$tmplog"

#cat $tmplog | mail -s $subject "bethany@diamantegraphix.com"

cat "$tmplog" >> "$logfile"

#rm "$tmplog"

echo " " >> $logfile
echo " " >> $logfile

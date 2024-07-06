#! /usr/bin/env sh

# restic password (optional)
RESTIC_PASSWORD=${RESTIC_PASSWORD:-""}

# Database Credentials
DB_HOST=${DB_HOST?Variable not set}
DB_NAME=${DB_NAME?Variable not set}
DB_USERNAME=${DB_USERNAME?Variable not set}
DB_PASSWORD=${DB_PASSWORD?Variable not set}

# Destinations
BACKUP_DIR=${BACKUP_DIR:-"/backups"}
if [ -z "$RESTIC_PASSWORD" ]; then
    BACKUP_FILE="${BACKUP_DIR}/${DB_NAME}-$(date +%Y%m%d%H%M%S).sql"
else
    BACKUP_FILE="/tmp/${DB_NAME}.sql"
fi

# Rclone remote (optional)
RCLONE_REMOTE=${RCLONE_REMOTE:-""}
RCLONE_CONFIG=${RCLONE_CONFIG:-"/rclone.conf"}

# Create backup dir if it doesn't exist
mkdir -p "$BACKUP_DIR"

# Perform the database dump based on what db utility is installed
if command -v mysqldump >/dev/null 2>&1; then
    mysqldump -h "$DB_HOST" -P "${DB_PORT:-"3306"}" -u "$DB_USERNAME" -p"$DB_PASSWORD" "$DB_NAME" > "$BACKUP_FILE"
elif command -v pg_dump >/dev/null 2>&1; then 
    export PGPASSWORD="$DB_PASSWORD"
    pg_dump -h "$DB_HOST" -p "${DB_PORT:-"5432"}" -U "$DB_USERNAME" "$DB_NAME" > "$BACKUP_FILE"
else
    echo "This condition should be impossible to reach... What did you do??!!"
    exit 1
fi

# Check if the dump was successful
if [ $? -eq 0 ]; then 
    echo "Database dump successful: ${BACKUP_FILE}"
else
    echo "Database dump failed"
    exit 1
fi

# Backup file using Restic if $RESTIC_PASSWORD is set
if [ -n "$RESTIC_PASSWORD" ]; then
    echo "$RESTIC_PASSWORD" > /tmp/restic_password

    # Initialize restic repo if it doesn't exist
    if ! restic --repo "$BACKUP_DIR" snapshots --password-file=/tmp/restic_password &>/dev/null; then 
        restic init --repo "$BACKUP_DIR" --password-file=/tmp/restic_password
    fi

    # Backup sql dump file
    cat "$BACKUP_FILE" | restic --repo "$BACKUP_DIR" backup --stdin --stdin-filename="${DB_NAME}.sql" --tag "sqldump" --host "dbackup" --password-file=/tmp/restic_password

    # Cleanup  
    [ -n "$RESTIC_PRUNE_ARGS" ] && restic --repo "$BACKUP_DIR" forget --password-file=/tmp/restic_password $RESTIC_PRUNE_ARGS --prune

    rm /tmp/restic_password $BACKUP_FILE
fi

# Sync backup dir to remote using Rclone if $RCLONE_REMOTE is set
if [ -n "$RCLONE_REMOTE" ]; then
    # https://github.com/rclone/rclone/issues/6656
    cp "$RCLONE_CONFIG" /tmp/rclone.conf

    rclone --config=/tmp/rclone.conf sync "$BACKUP_DIR" "$RCLONE_REMOTE"

    if [ $? -eq 0 ]; then 
        echo "Rclone sync to remote successful"
        rm /tmp/rclone.conf
    else
        echo "Rclone sync to remote failed"
        rm /tmp/rclone.conf
        exit 1
    fi
fi

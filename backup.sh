#!/bin/bash

##
# Backup PgSQL
# Author: Matthew Spurrier
# Website: http://www.digitalsparky.com/
##

## START CONFIG
BACKUPPATH='/opt/pgsql-backup'
KEEPFOR=7

## END CONFIG

CMD=${1-"--help"}
PGSQLBIN="$(which psql)"
PGSQLDUMPBIN="$(which pg_dump)"
PGRESTOREBIN="$(which pg_restore)"
EGREPBIN="$(which egrep)"
PGSQL="sudo -u postgres ${PGSQLBIN} -U postgres"
PGDUMPCMD="sudo -u postgres ${PGSQLDUMPBIN} -U postgres -F c -Z 9 -x -E UTF8 -b"
PGRESTORE="sudo -u postgres ${PGRESTOREBIN} -U postgres"
CULLKEEPFOR=${KEEPFOR-"30"}
PID=$$

# PGSQLDUMP
if [ ! -x "${PGSQLDUMPBIN}" ]; then
    echo "pg_dump is missing or non-executable and is required for this to run, this package is provided by postgresql-client, please resolve this."
    exit 1
fi
# PGSQL
if [ ! -x "${PGSQLBIN}" ]; then
    echo "psql is missing or non-executable and is required for this to run, this package is provided by postgresql-client, please resolve this."
    exit 1
fi
# EGrep
if [ ! -x "${EGREPBIN}" ]; then
    echo "egrep is missing or non-executable and is required for this to run, please resolve this."
    exit 1
fi

printHelp () {
    cat <<EOF
PgSQL Backup Script
Usage: $0 [--help|--clean|--backup|--restore]

--clean: Run's backup cull/cleanup job
--backup [database]: Runs backup job (leave 'database' variable to run all)
--restore [restorefile] [newdatabase]: Restore's an archive to the new database name

EOF
    exit 1
}

msg () {
    TIME=$(date +"%D %T")
    case $2 in
        0)
            echo -ne "[ ${TIME} ] $1\r"
            ;;
        1)
            echo -e "\t\t\t\t\t\t\t\t\t\t [ $1 ]"
            ;;
        *)
            echo "[ ${TIME} ] $1"
            ;;
    esac

}

backupDB () {
    DATE=$(date +%Y%m%d)
    HOUR=$(date +%H)
    HOURBACKUP="${BACKUPPATH}/${DBNAME}/${DATE}/${HOUR}.dump"
    msg "Beginning backup of ${DBNAME}"
    if [ ! -d "${BACKUPPATH}/${DBNAME}/${DATE}" ]; then
        mkdir -p "${BACKUPPATH}/${DBNAME}/${DATE}"
        if [ "$?" -ne 0 ]; then
            echo "Failed to create backup path" >&2
            exit 1
        fi
    fi
    msg "Creating hourly backup for ${DATE} at ${HOUR}" 0
    if [ -f "${HOURBACKUP}" ]; then
        msg "FAILED" 1
        echo "This hours backup has already been run, exiting." >&2
        exit 1
    fi
    PIDFILE="${BACKUPPATH}/${DBNAME}-${DATE}-${HOUR}.pid"
    if [ ! -f "${PIDFILE}" ]; then
        echo "${PID}" > "${PIDFILE}"
    else
        CHECKPID=$(cat "${PIDFILE}" 2>/dev/null 3>/dev/null)
        if [ $(ps -p "${CHECKPID}" > /dev/null 2>&1 3>&1; echo $?) -eq 0 ]; then
            msg "FAILED" 1
            echo "This hours backup has already been run, and is still running, exiting." >&2
            exit 1
        fi
    fi
    chown -R postgres:postgres "${BACKUPPATH}"
    ${PGDUMPCMD} -f "${HOURBACKUP}" "${DBNAME}" > /dev/null 2>&1
    if [ "$?" -ne 0 ]; then
        msg "FAILED" 1
        echo "Failed to create backup of ${DBNAME}" >&2
        rm "${PIDFILE}"
        exit 1
    fi
    msg "OK" 1
    rm "${PIDFILE}"
    msg "Backup of ${DBNAME} completed successfully"
}

cleanup () {
    for FILE in $(find "${BACKUPPATH}" -maxdepth 2 -mindepth 2 -type d -mtime +"${CULLKEEPFOR}" -print); do
        rm -rf "${FILE}"
    done
}

restoreDB () {
    msg "Restoring ${RESTOREFILE} to ${DBNAME}" 0
    ${PGRESTORE} -d "${DBNAME}" "${RESTOREFILE}"
    if [ "$?" -ne 0 ]; then
        msg "FAILED" 1
        echo "Failed to restore ${RESTOREFILE} to ${DBNAME}" >&2
        exit 1
    fi
    msg "OK" 1
    msg "Restore of ${RESTOREFILE} to ${DBNAME} completed successfully"
}

case "${CMD}" in
    "--help")
        printHelp
        ;;
    "--clean")
        cleanup
        ;;
    "--restore")
        if [ -n "$2" ]; then
            if [ ! -f "$2" ]; then
                echo "Please specify restore file path"
                exit 1
            fi
            RESTOREFILE="$2"
        else
            echo "Please specify restore file path"
            exit 1
        fi
        DBLIST=$(${PGSQL} -c "SELECT datname FROM pg_database ORDER BY 1;" -t -A 2>/dev/null | ${EGREPBIN} -vie "postgres|template0|template1")
        if [ -n "$3" ]; then
            echo "${DBLIST}" | grep "$3" > /dev/null 2>&1
            if [ "$?" -ne 0 ]; then
                echo "Specificied database '$3' does not exist" >&2
                exit 1
            else
                DBNAME="$3"
            fi
        else
            echo "Please specify destination db"
            exit 1
        fi
        restoreDB
        ;;
    "--backup")
        DBLIST=$(${PGSQL} -c "SELECT datname FROM pg_database ORDER BY 1;" -t -A 2>/dev/null | ${EGREPBIN} -vie "postgres|template0|template1")
        if [ "$?" -ne 0 ]; then
            echo "Unable to get database list, this means backups can't run!!" >&2
            exit 1
        fi
        if [ -n "$2" ]; then
            echo "${DBLIST}" | grep "$2" > /dev/null 2>&1
            if [ "$?" -ne 0 ]; then
                echo "Specificied database '$2' does not exist" >&2
                exit 1
            else
                DBNAME="$2"
                backupDB
            fi
        else
            for DBNAME in ${DBLIST}; do
                $0 --backup "${DBNAME}"
            done
        fi
        ;;
    *)
        printHelp
        ;;
esac


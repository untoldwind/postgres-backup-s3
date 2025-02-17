#!/bin/bash
set -e
set -o pipefail

# Date function
get_date () {
    date +[%Y-%m-%d\ %H:%M:%S]
}

# Script
: ${GPG_KEYSERVER:='keyserver.ubuntu.com'}
: ${GPG_KEYID:=''}
: ${COMPRESS:='pigz'}
: ${MAINTENANCE_DB:='postgres'}
START_DATE=`date +%Y-%m-%d_%H-%M-%S`

if [ -z "$GPG_KEYID" ]
then
    echo "$(get_date) !WARNING! It's strongly recommended to encrypt your backups."
else
    echo "$(get_date) Preparing keys: importing from keyserver"
    gpg --keyserver ${GPG_KEYSERVER} --recv-keys ${GPG_KEYID}
fi

echo "$(get_date) Postgres backup started"

export MC_HOST_backup="https://${AWS_ACCESS_KEY_ID}:${AWS_SECRET_ACCESS_KEY}@s3.${AWS_REGION}.amazonaws.com"
export PGPASSWORD="${DB_PASSWORD}"

mc mb backup/${S3_BUCK} --insecure || true

case $COMPRESS in
  'pigz' )
      COMPRESS_CMD='pigz -9'
      COMPRESS_POSTFIX='.gz'
    ;;
  'xz' )
      COMPRESS_CMD='xz'
      COMPRESS_POSTFIX='.xz'
    ;;
  'bzip2' )
      COMPRESS_CMD='bzip2 -9'
      COMPRESS_POSTFIX='.bz2'
    ;;
  'lrzip' )
      COMPRESS_CMD='lrzip -l -L5'
      COMPRESS_POSTFIX='.lrz'
    ;;
  'brotli' )
      COMPRESS_CMD='brotli -9'
      COMPRESS_POSTFIX='.br'
    ;;
  'zstd' )
      COMPRESS_CMD='zstd -9'
      COMPRESS_POSTFIX='.zst'
    ;;
  * )
      echo "$(get_date) Invalid compression method: $COMPRESS. The following are available: pigz, xz, bzip2, lrzip, brotli, zstd"
      exit 1
    ;;
esac

dump_db(){
  DATABASE=$1
  # Ping databaase
  psql -h "${DB_HOST}" -U "${DB_USER}" -d "${DATABASE}" -c ''

  echo "$(get_date) Dumping database: $DATABASE"

  if [ -z "$GPG_KEYID" ]
  then
    pg_dump -h "${DB_HOST}" -U "${DB_USER}" -d "${DATABASE}" | $COMPRESS_CMD | mc pipe backup/${S3_BUCK}/${S3_NAME}-${START_DATE}-${DATABASE}.pgdump${COMPRESS_POSTFIX} --insecure
  else
    pg_dump -h "${DB_HOST}" -U "${DB_USER}" -d "${DATABASE}" | $COMPRESS_CMD \
    | gpg --encrypt -z 0 --recipient ${GPG_KEYID} --trust-model always \
    | mc pipe backup/${S3_BUCK}/${S3_NAME}-${START_DATE}-${DATABASE}.pgdump${COMPRESS_POSTFIX}.pgp --insecure
  fi
}

dump_db "$DB_NAME"

echo "$(get_date) Postgres backup completed successfully"

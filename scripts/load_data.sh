#! /bin/bash
set -e
mkdir /tmp/workspace
cat $1 | head -n 1 > /tmp/workspace/header
cat $1 | head -n 10000 > /tmp/workspace/$2
cat $1 | tail -n +10001 | split -d -l 10000 - /tmp/workspace/_part_
csvsql \
--db $3 \
--db-schema $4 \
--create-if-not-exists \
--no-constraints \
--insert /tmp/workspace/$2
if [ "$(ls -A /tmp/workspace/_part_*)" ]; then
  for file in /tmp/workspace/_part_*; do
    cp /tmp/workspace/header /tmp/workspace/$2
    cat $file >> /tmp/workspace/$2
    csvsql \
    --db $3 \
    --db-schema $4 \
    -y -1 \
    --no-create \
    --no-inference \
    --insert /tmp/workspace/$2
  done
fi

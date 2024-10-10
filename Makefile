#
# Phony targets should never be stale.
# If the command is per-branch, touch empty files under .cache/${NAMESPACE}/make/$@.
# Example:
#
# .PHONY: my-target
# 	echo "this command does something"
# 	touch .cache/${NAMESPACE}/make/my-target
#
#	.cache/${NAMESPACE}/make/my-target: path/to/some/dependency.txt
#		$(MAKE) go-sqlc
#
# Now the user can call `make my-target` to force a re-run; Or it can be used as a dependency like this:
#
#	.PHONY: do-something
#	do-something: .cache/${NAMESPACE}/make/my-target
#		echo "my-target is updated only if needed and now I'm doing something"
#

RANDOM_PORT_1:=$(shell shuf -i 1024-65535 -n 1)
RANDOM_PORT_2:=$(shell shuf -i 1024-65535 -n 1)

DATASETS=$(shell find assets/datasets -not -path './.cache*' -iname '*.csv')
DATASET_TARGETS=$(shell echo ${DATASETS} | sed 's#assets/datasets/#.cache/${NAMESPACE}/make/load-datasets/#g' | sed 's/\.csv//g' )
# SEARCH_PATH=$(shell echo ${DATASETS} | sed 's#assets/datasets/\([^/]*\)/[^ ]*#\1,#g' )
SQLC_QUERIES=$(shell find db/sqlc -not -path './.cache*' -iname '*.sql' | grep -v schema.sql)
MIGRATE_PATH=db/migrations
MIGRATIONS=$(shell find ${MIGRATE_PATH} -not -path './.cache*' -iname '*.sql')

# overrideable by environment variables
DATA_DIRECTORY?=${PWD}/.cache/${NAMESPACE}/data
DB_CONN_STRING?=postgresql://${PGUSER}:${PGPASSWORD}@${PGHOST}:${PGPORT}/${PGDATABASE}?sslmode=disable
NAMESPACE?=fantasy-$(shell git rev-parse --abbrev-ref HEAD)
NETWORK?=${NAMESPACE}
PGDATABASE?=postgres
PGHOST?=${NAMESPACE}-db
PGPASSWORD?=changeme
PGPORT?=5432
PGUSER?=user
POSTGRES_VERSION?=16.4
PROMPT_MIGRATION?=$(shell bash -c 'read -p "Migration Identifier: " migration; echo $$migration')
SQLC_VERSION?=1.27.0
GOMIGRATE_VERSION?=v4.18.1
MIGRATE_VERSION_FILE?=$(shell ls "${PWD}/${MIGRATE_PATH}" | sort -t '_' -k 1 -n | tail -n 1)
MIGRATE_VERSION?=$(shell echo "${MIGRATE_VERSION_FILE}" | sed -E 's|([0-9]*)_.*.sql|\1|')
PROMPT_MIGRATION_NAME?=$(shell bash -c 'read -p "Descriptive Filename Part (e.g. sphincs_private_ica): " migration; echo $$migration')
PGADMIN_DEFAULT_EMAIL?=admin@${PGHOST}.com
PGADMIN_DEFAULT_PASSWORD?=${PGPASSWORD}
PGADMIN_PORT?=$(strip $(shell docker container inspect --format='{{(index (index .NetworkSettings.Ports "80/tcp") 0).HostPort}}' ${PGHOST}-pgadmin 2>/dev/null || echo "${RANDOM_PORT_1}"))
PG_HOST_PORT?=$(strip $(shell docker container inspect --format='{{(index (index .NetworkSettings.Ports "80/tcp") 0).HostPort}}' ${PGHOST}-pgadmin 2>/dev/null || echo "${RANDOM_PORT_2}"))
PGADMIN_VERSION?=8.12.0
BROWSER?="Google Chrome"
GO_VERSION?=$(shell head -n 3 go.mod | xargs -n 1 | tail -n 1)
GO_REPO_URL=$(shell head -n 1 go.mod | xargs -n 1 | tail -n 1)
LOCAL_PG_PORT=$(shell docker container inspect --format='{{(index (index .NetworkSettings.Ports "${PGPORT}/tcp") 0).HostPort}}' ${PGHOST})
LOCAL_DB_CONN_STRING?=postgresql://${PGUSER}:${PGPASSWORD}@localhost:${LOCAL_PG_PORT}/${PGDATABASE}?sslmode=disable

.PHONY: debug
debug:
	echo ${DATASET_TARGETS}

.DEFAULT_GOAL=help
.PHONY: help
help: ## Show this help.
	@echo "Make Commands:"
	@echo "---"
	@echo
	@cat $(MAKEFILE_LIST) | grep '^[a-z].*:.*##' | sed 's/\(.*\):.*##\(.*\)/* `make \1`:\2/'

.PHONY: run-dev-draft
run-dev-draft: .cache/${NAMESPACE}/make/postgres-migrate load-datasets .cache/${NAMESPACE}/make/go-sqlc ## Run dev.
	@mkdir -p .cache/${NAMESPACE}/go/mod
	@mkdir -p .cache/${NAMESPACE}/go/go-build
	docker run \
		--interactive \
		--tty \
		--rm \
		--network '${NETWORK}' \
		--env DB_CONN_STRING=${DB_CONN_STRING} \
		--volume ${PWD}/.cache/${NAMESPACE}/go/mod:/go/pkg/mod \
		--volume ${PWD}/.cache/${NAMESPACE}/go/go-build:/root/.cache/go-build \
		--volume ${PWD}:/go/src/${GO_REPO_URL} \
		--workdir /go/src/${GO_REPO_URL} \
	golang:${GO_VERSION} go run cmd/draft/*.go

.PHONY: go-sqlc
go-sqlc: db/sqlc/schema.sql ## Generate go code from sqlc.
	- rm db/sqlc/*.sql.go
	docker run \
		--interactive \
		--tty \
		--rm \
		--volume ${PWD}:/repo \
		--workdir /repo/db/sqlc \
	sqlc/sqlc:${SQLC_VERSION} generate
	@mkdir -p .cache/${NAMESPACE}/make
	@touch .cache/${NAMESPACE}/make/go-sqlc

.PHONY: load-datasets
load-datasets: postgres-wait docker-fantasy-csvkit ${DATASET_TARGETS} ## All of the data under `assets/datasets/%.csv` will get loaded into the postgresql database.

.PHONY: postgres-start
postgres-start: docker-network ## Start postgres if it isn't started and return immediately.
	@mkdir -p ${DATA_DIRECTORY}
	docker container inspect --format='postgres is {{.State.Status}}' ${PGHOST} || docker run \
		--detach \
		--name ${PGHOST} \
		--rm \
		--publish ${PG_HOST_PORT}:${PGPORT} \
		--env POSTGRES_PASSWORD=${PGPASSWORD} \
		--env POSTGRES_USER=${PGUSER} \
		--env POSTGRES_DB=${PGDATABASE} \
		--env PGDATA=/var/lib/postgresql/data/pgdata \
		--network '${NETWORK}' \
		--volume ${DATA_DIRECTORY}:/var/lib/postgresql/data \
		postgres:${POSTGRES_VERSION}

.PHONY: psql-local
psql-local: postgres-wait ## Start an interactive postgres shell using local psql
		psql \
			-d ${LOCAL_DB_CONN_STRING} \
			--pset expanded=auto \
			-f -

.PHONY: psql
psql: postgres-wait ## Start an interactive postgres shell
	docker run \
		--name ${PGHOST}-psql \
		--interactive \
		--tty \
		--rm \
		--network '${NETWORK}' \
		postgres:${POSTGRES_VERSION} psql \
			-d ${DB_CONN_STRING} \
			--pset expanded=auto \
			-f -

.PHONY: pgadmin
pgadmin: postgres-wait ## Start pgadmin and open in browser window
	@mkdir -p ${PWD}/.cache/${NAMESPACE}/pgadmin/state
	@echo ' { "Servers": { "1": { "Name": "${NAMESPACE}", "Group": "Servers", "Host": "${PGHOST}", "Port": ${PGPORT}, "Username": "${PGUSER}", "SSLMode": "prefer", "MaintenanceDB": "${PGDATABASE}", "PassFile": "/pgpass" } } } ' > ${PWD}/.cache/${NAMESPACE}/pgadmin/servers.json
	@echo '${PGHOST}:${PGPORT}:${PGDATABASE}:${PGUSER}:${PGPASSWORD}' > ${PWD}/.cache/${NAMESPACE}/pgadmin/pgpass
	@chmod 600 ${PWD}/.cache/${NAMESPACE}/pgadmin/pgpass
	@echo "admin email: ${PGADMIN_DEFAULT_EMAIL}"
	@echo "admin password: ${PGADMIN_DEFAULT_PASSWORD}"
	docker container inspect --format='pgadmin is {{.State.Status}} at port {{(index (index .NetworkSettings.Ports "80/tcp") 0).HostPort}}' ${PGHOST}-pgadmin || docker run \
		--name ${PGHOST}-pgadmin \
		--rm \
		--detach \
		--network '${NETWORK}' \
		--env PGADMIN_CONFIG_SERVER_MODE=False \
		--env PGADMIN_CONFIG_MASTER_PASSWORD_REQUIRED=False \
		--env PGADMIN_DEFAULT_EMAIL=${PGADMIN_DEFAULT_EMAIL} \
		--env PGADMIN_DEFAULT_PASSWORD=${PGADMIN_DEFAULT_PASSWORD} \
		--volume ${PWD}/.cache/${NAMESPACE}/pgadmin/state:/var/lib/pgadmin \
		--volume ${PWD}/.cache/${NAMESPACE}/pgadmin/servers.json:/pgadmin4/servers.json \
		--volume ${PWD}/.cache/${NAMESPACE}/pgadmin/pgpass:/pgpass \
		--publish ${PGADMIN_PORT}:80 \
		dpage/pgadmin4:${PGADMIN_VERSION}
	until curl "http://localhost:${PGADMIN_PORT}"; \
	do \
			sleep 3; \
	done
	open -a ${BROWSER} "http://localhost:${PGADMIN_PORT}"

.PHONY: pgadmin-stop
pgadmin-stop: ## Stop running pgadmin instance
	docker stop ${PGHOST}-pgadmin

.PHONY: postgres-stop
postgres-stop: ## Stop running postgres instance
	docker stop ${PGHOST}

.PHONY: postgres-wait
postgres-wait: postgres-start ## Start postgres if it isn't started and wait for it to be ready.
	until docker run \
		--name ${PGHOST}-wait \
		--rm \
		--network '${NETWORK}' \
		postgres:${POSTGRES_VERSION} psql -d ${DB_CONN_STRING} -c 'SELECT 1'; \
	do \
			sleep 3; \
	done

.PHONY: docker-fantasy-csvkit
docker-fantasy-csvkit:
	docker image inspect \
		--format 'docker image fantasy-csvkit was created on {{.Created}}' \
		fantasy-csvkit || docker build --tag fantasy-csvkit --file docker/csvkit .

.PHONY: docker-network
docker-network:
	docker network inspect \
		--format 'docker network ${NETWORK} was created on {{.Created}}' \
		${NETWORK} || docker network create ${NETWORK}

.PHONY: postgres-schema-dump
postgres-schema-dump: .cache/${NAMESPACE}/make/postgres-migrate ## create postgres schema dump file under db/sqlc, which is necessary for sqlc
	$(MAKE) postgres-wait
	docker run \
		--interactive \
		--tty \
		--rm \
		--name ${PGHOST}-pgschema-dump \
		--network '${NETWORK}' \
		--env PGDATABASE=${PGDATABASE} \
		--env PGHOST=${PGHOST} \
		--env PGPASSWORD=${PGPASSWORD} \
		--env PGPORT=${PGPORT} \
		--env PGUSER=${PGUSER} \
		--volume ${PWD}/db:/db \
		--workdir / \
		postgres:${POSTGRES_VERSION} pg_dump \
			--file db/sqlc/schema.sql \
			--schema-only

.PHONY: postgres-migrate-create
postgres-migrate-create: postgres-wait ## Helps the user create a pair of up/down migration script files and prompts them for a descriptive filename.
	docker run \
		--interactive \
		--tty \
		--rm \
		--name ${PGHOST}-postgres-migrate-create \
		--network '${NETWORK}' \
		--volume ${PWD}/${MIGRATE_PATH}:/${MIGRATE_PATH} \
		migrate/migrate:${GOMIGRATE_VERSION} \
			-database ${DB_CONN_STRING} \
			-path /${MIGRATE_PATH} \
			create \
				-ext sql \
				-dir /${MIGRATE_PATH} \
				-seq \
				-digits 3 \
				${PROMPT_MIGRATION_NAME}

.PHONY: postgres-migrate
postgres-migrate: postgres-wait ## Run all migrations up to the latest version.
	docker run \
		--interactive \
		--tty \
		--rm \
		--name ${PGHOST}-postgres-migrate \
		--network '${NETWORK}' \
		--volume ${PWD}/${MIGRATE_PATH}:/${MIGRATE_PATH} \
		migrate/migrate:${GOMIGRATE_VERSION} \
			-database ${DB_CONN_STRING} \
			-path /${MIGRATE_PATH} \
			goto ${MIGRATE_VERSION}
	@mkdir -p .cache/${NAMESPACE}/make
	@touch .cache/${NAMESPACE}/make/postgres-migrate

.PHONY: postgres-migrate-version
postgres-migrate-version: postgres-wait ## Print the currently applied migration version.
	docker run \
		--interactive \
		--tty \
		--rm \
		--name ${PGHOST}-postgres-migrate-version \
		--network '${NETWORK}' \
		--volume ${PWD}/${MIGRATE_PATH}:/${MIGRATE_PATH} \
		migrate/migrate:${GOMIGRATE_VERSION} \
			-database ${DB_CONN_STRING} \
			-path /${MIGRATE_PATH} \
			version

.PHONY: postgres-migrate-force
postgres-migrate-force: postgres-wait ## Force the migration to a specific version. This is useful in case of a failed migration.
	docker run \
		--interactive \
		--tty \
		--rm \
		--name ${PGHOST}-postgres-migrate-force \
		--network '${NETWORK}' \
		--volume ${PWD}/${MIGRATE_PATH}:/${MIGRATE_PATH} \
		migrate/migrate:${GOMIGRATE_VERSION} \
			-database ${DB_CONN_STRING} \
			-path /${MIGRATE_PATH} \
			force ${MIGRATE_VERSION}


# generated files

db/sqlc/schema.sql: .cache/${NAMESPACE}/make/postgres-migrate
	$(MAKE) postgres-schema-dump

# namespaced make targets

.cache/${NAMESPACE}/make/load-datasets/%: assets/datasets/%.csv
	docker run \
		--name ${PGHOST}-wait \
		--rm \
		--network '${NETWORK}' \
		postgres:${POSTGRES_VERSION} psql \
			-d ${DB_CONN_STRING} \
			-c 'CREATE SCHEMA IF NOT EXISTS $(*D)';
	docker run \
		--name ${PGHOST}-wait \
		--rm \
		--network '${NETWORK}' \
		--volume ${PWD}/assets/datasets:/workdir/assets/datasets \
		--volume ${PWD}/scripts/load_data.sh:/workdir/load_data.sh \
		--workdir /workdir \
		fantasy-csvkit ./load_data.sh $< $(@F) ${DB_CONN_STRING} $(*D)
	@mkdir -p $(@D)
	@touch $@

.cache/${NAMESPACE}/make/go-sqlc: ${SQLC_QUERIES}
	$(MAKE) go-sqlc

.cache/${NAMESPACE}/make/postgres-migrate:
	$(MAKE) postgres-migrate

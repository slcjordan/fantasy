# Fantasy
This project contains scripts and a makefile for loading fantasy sports data
into a database, manage weekly lineups, etc. I do my development on Mac/XCode
so there may be some incompatibility with other versions of unix tooling.

GNU Make 4.4.1
Built for aarch64-apple-darwin23.5.0


## Prerequisites
- [make](https://www.gnu.org/software/make/)
- [docker](https://www.gnu.org/software/make/)


## Dev Prerequisites
- [go](https://go.dev)
- [direnv](https://direnv.net/)


## Getting started

1. Store datasets under the following directory structure:
```
assets/
└── datasets
    ├── espn
    │   └── player.csv
    └── htbb
        └── player.csv
```

Here's an example of what one of these files looks like:
```
$ head assets/datasets/espn/player.csv

rank,player,team,pos,gp,min,fg_pct,ft_pct,3pm,reb,ast,a_to_to,stl,blk,top,ts,fpts
1,"Nikola Jokic","Den","C",77,35.1,.590,.817,1.0,12.7,9.2,2.79,1.4,0.8,3.3,26.7,7260
2,"Luka Doncic","Dal","PG",72,37.0,.486,.772,3.7,9.1,9.3,2.33,1.4,0.5,4.0,33.1,7572
3,"Shai Gilgeous-Alexander","OKC","PG",74,34.8,.532,.875,1.4,5.6,6.8,2.96,2.0,0.9,2.3,32.0,7111
4,"Victor Wembanyama","SA","C",70,33.4,.491,.820,2.1,12.0,4.4,1.07,1.8,4.3,4.1,25.4,6874
5,"Giannis Antetokounmpo","Mil","PF C",70,35.4,.595,.660,0.6,11.9,6.5,1.81,1.1,1.1,3.6,31.3,6784
6,"Domantas Sabonis","Sac","C PF",80,36.1,.595,.714,0.4,13.6,8.0,2.42,0.9,0.6,3.3,19.6,6046
7,"Tyrese Haliburton","Ind","PG SG",70,34.8,.479,.857,3.0,4.2,11.5,4.60,1.4,0.7,2.5,21.4,5702
8,"Joel Embiid","Phi","C",60,34.4,.530,.866,1.3,11.0,5.1,1.38,1.1,1.7,3.7,34.1,6112
9,"Jayson Tatum","Bos","PF SF",76,36.0,.468,.840,3.1,8.2,4.8,1.84,1.0,0.6,2.6,27.5,6253
```

2. Load datasets. The schema gets inferred by the directory name. The table is
   inferred by the filename. Assumes first line is column names. Column
datatypes are inferred by [csvkit](https://csvkit.readthedocs.io/). Schemas can
be set explicitly by [Schema Migrations](#schema_migrations).

```
make load-datasets
```

3. Explore tables.

```
make psql

postgres=# SELECT
  table_schema,
  table_name
FROM information_schema.tables
WHERE table_schema not in
(
 'pg_catalog',
 'information_schema'
);

--------------+------------
 espn         | player
 htbb         | player
(2 rows)

```


## Project-Specific Makefile Quirks
All persistent state (database, etc is stored under .cache/$NAMESPACE with
NAMESPACE set to `fantasy-$(shell git rev-parse --abbrev-ref HEAD)` e.g.
`.cache/fantasy-master` for the master branch. This makes it so you can run
separate dev environments for each of your branches.

Here are several useful environment variables that can be customized in your
local shell. (Full list is at the top of the Makefile):

- `$BROWSER`: some commands (e.g. `make pgadmin`) will run `open -a $BROWSER`.
- `$PGUSER`: use a custom postgres user.
- `$PGPASSWORD`: use a custom postgres password.


## Schema Migrations

1. Create an empty schema migration under `db/migrations`
```
make postgres-migrate-create
```

2. Run schema migration
```
make postgres-migrate
```


## Make Commands:
- `make help`: Show this help.
- `make run-dev-draft`: Run dev.
- `make go-sqlc`: Generate go code from sqlc.
- `make load-datasets`: All of the data under `assets/datasets/%.csv` will get loaded into the postgresql database.
- `make postgres-start`: Start postgres if it isn't started and return immediately.
- `make psql-local`: Start an interactive postgres shell using local psql
- `make psql`: Start an interactive postgres shell
- `make pgadmin`: Start pgadmin and open in browser window
- `make pgadmin-stop`: Stop running pgadmin instance
- `make postgres-stop`: Stop running postgres instance
- `make postgres-wait`: Start postgres if it isn't started and wait for it to be ready.
- `make postgres-schema-dump`: create postgres schema dump file under db/sqlc, which is necessary for sqlc
- `make postgres-migrate-create`: Helps the user create a pair of up/down migration script files and prompts them for a descriptive filename.
- `make postgres-migrate`: Run all migrations up to the latest version.
- `make postgres-migrate-version`: Print the currently applied migration version.
- `make postgres-migrate-force`: Force the migration to a specific version. This is useful in case of a failed migration.

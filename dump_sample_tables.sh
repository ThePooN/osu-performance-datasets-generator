#!/bin/bash
# Select relevant sample users and dump to a file.

source ./globals.sh

RULESET=$1
SAMPLE=$2
USER_COUNT=$3

sql() {
    mysql osu -sN -h "${DATABASE_HOST}" -u "${DATABASE_USER}" -e "SELECT('$1'); $2; SELECT CONCAT('✓ Completed with ', ROW_COUNT(), ' rows.');"
}

dump() {
    echo "Dumping $1..."
    path=${output_folder}/${1}.sql
    mysqldump --set-gtid-purged=OFF --single-transaction -h "${DATABASE_HOST}" -u "${DATABASE_USER}" osu $1 --where="${2:-1=1}" > ${path}
    echo "✓ Completed with $(stat -c%s "${path}") bytes."
}

case "$RULESET" in
    osu)
        mode_index=0
        suffix="_osu"
        main_suffix="_osu"
        table_suffix=""
        name="osu!"
        ;;
    taiko)
        mode_index=1
        suffix="_taiko"
        main_suffix="_taiko"
        table_suffix=$suffix
        name="osu!taiko"
        ;;
    catch)
        mode_index=2
        suffix="_fruits"
        main_suffix="_catch"
        table_suffix=$suffix
        name="osu!catch"
        ;;
    mania)
        mode_index=3
        suffix="_mania"
        main_suffix="_mania"
        table_suffix=$suffix
        name="osu!mania"
        ;;
esac

sample_users_table="sample_users"
sample_beatmapsets_table="sample_beatmapsets${table_suffix}"
sample_beatmaps_table="sample_beatmaps${table_suffix}"

output_folder="${DATE}_performance${main_suffix}_${SAMPLE}_${USER_COUNT}"

# WHERE clause to exclude invalid beatmaps
beatmap_set_validity_check="approved > 0 AND deleted_at IS NULL"
beatmap_validity_check="approved > 0 AND deleted_at IS NULL"
user_validity_check="user_warnings = 0 AND user_type != 1"

echo
echo "Creating dump for $name (${output_folder})"
echo

# create sample users table

sql "Creating sample_users table"         "DROP TABLE IF EXISTS ${sample_users_table}; CREATE TABLE ${sample_users_table} ( user_id INT PRIMARY KEY, username varchar(255) CHARACTER SET utf8 NOT NULL DEFAULT '', user_warnings tinyint(4) NOT NULL DEFAULT '0', user_type tinyint(2) NOT NULL DEFAULT '0' )"
sql "Creating sample_beatmapsets table"   "DROP TABLE IF EXISTS ${sample_beatmapsets_table}; CREATE TABLE ${sample_beatmapsets_table} ( beatmapset_id INT PRIMARY KEY );"
sql "Creating sample_beatmaps table"      "DROP TABLE IF EXISTS ${sample_beatmaps_table}; CREATE TABLE ${sample_beatmaps_table} ( beatmap_id INT PRIMARY KEY );"

if [ "$SAMPLE" == "random" ] ; then
    sql "Populating random users.."     "INSERT IGNORE INTO ${sample_users_table} (user_id) SELECT user_id FROM osu_user_stats${table_suffix} WHERE rank_score > 0 ORDER BY RAND(1) LIMIT $USER_COUNT;"
else
    sql "Populating top users.."        "INSERT IGNORE INTO ${sample_users_table} (user_id) SELECT user_id FROM osu_user_stats${table_suffix} ORDER BY rank_score desc LIMIT $USER_COUNT"
fi

sql "Adding user details.."         "REPLACE INTO ${sample_users_table} SELECT user_id, username, user_warnings, user_type FROM phpbb_users WHERE user_id IN (SELECT user_id FROM ${sample_users_table})"

sql "Removing restricted users.."   "DELETE FROM ${sample_users_table} WHERE ${sample_users_table}.user_id NOT IN (SELECT user_id FROM phpbb_users WHERE ${user_validity_check});"
sql "Populating beatmapsets.."      "INSERT IGNORE INTO ${sample_beatmapsets_table} SELECT beatmapset_id FROM osu_beatmapsets WHERE ${beatmap_set_validity_check};"
sql "Populating beatmaps.."         "INSERT IGNORE INTO ${sample_beatmaps_table} SELECT beatmap_id FROM osu_beatmaps WHERE ${beatmap_validity_check} AND beatmapset_id IN (SELECT beatmapset_id FROM ${sample_beatmapsets_table});"

mkdir -p ${output_folder}

echo

# user stats (using sample users retrieved above)
dump "${sample_users_table}"
dump "osu_scores${table_suffix}_high"   "user_id IN (SELECT user_id FROM ${sample_users_table})"
dump "osu_user_stats${table_suffix}"    "user_id IN (SELECT user_id FROM ${sample_users_table})"
dump "osu_user_beatmap_playcount"       "user_id IN (SELECT user_id FROM ${sample_users_table}) AND beatmap_id IN (SELECT beatmap_id FROM ${sample_beatmaps_table})"

# beatmap tables (we only care about ranked/approved/loved beatmaps)
dump "osu_beatmapsets"                  "beatmapset_id IN (SELECT beatmapset_id FROM ${sample_beatmapsets_table})"
dump "osu_beatmaps"                     "beatmap_id IN (SELECT beatmap_id FROM ${sample_beatmaps_table})"
dump "osu_beatmap_failtimes"                    "beatmap_id IN (SELECT beatmap_id FROM ${sample_beatmaps_table})"

# beatmap difficulty tables (following same ranked/approved/loved rule as above, plus only for the intended game mode)
dump "osu_beatmap_difficulty"           "mode = $mode_index AND beatmap_id IN (SELECT beatmap_id FROM ${sample_beatmaps_table})"
dump "osu_beatmap_difficulty_attribs"   "mode = $mode_index AND beatmap_id IN (SELECT beatmap_id FROM ${sample_beatmaps_table})"

# misc tables
dump "osu_difficulty_attribs"
dump "osu_beatmap_performance_blacklist"
dump "osu_counts"

echo

#clean up
sql "Dropping sample_users table.." "DROP TABLE ${sample_users_table}"
sql "Dropping sample_beatmaps table.." "DROP TABLE ${sample_beatmaps_table}"
sql "Dropping sample_beatmapsets table.." "DROP TABLE ${sample_beatmapsets_table}"

echo
echo "Compressing.."

tar -cvjSf ${output_folder}.tar.bz2 ${output_folder}/*
rm -r ${output_folder}

mv ${output_folder}.tar.bz2 ${OUTPUT_PATH}/

echo
echo "All done!"
echo

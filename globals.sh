#!/bin/bash

set -e

DATABASE_HOST="${DATABASE_HOST:-db-delayed}"
DATABASE_USER="${DATABASE_USER:-performance-export}"

S3_BUCKET="${S3_BUCKET:-data.ppy.sh}"

DATE=$(date +"%Y_%m_%d")

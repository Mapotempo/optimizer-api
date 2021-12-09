#!/bin/bash

find /srv/docker-data/optimizer-api/archives/dump/*test-bastard* -mtime +8 -delete
find /srv/docker-data/optimizer-api/archives/dump/ -mtime +30 -delete

find /srv/docker-data/optimizer-api-alpha/archives/dump/ -mtime +6 -delete

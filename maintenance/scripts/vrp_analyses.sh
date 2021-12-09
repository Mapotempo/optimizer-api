#!/usr/bin/env bash
file=$1

list_lat=$(jq -r '.vrp.points[] | "\(.location.lat)"' $file)
list_lon=$(jq -r '.vrp.points[] | "\(.location.lon)"' $file)

sort_lat=$(echo "$list_lat" | tr ' ' '\n' | sort -g )
nb_lat=$(echo "$list_lat" | tr ' ' '\n' | wc -l | xargs)
max_lat=$(awk '{print $NF}' <<< $sort_lat)
min_lat=$(awk '{print $1}' <<< $sort_lat)

sort_lon=$(echo "$list_lon" | tr ' ' '\n' | sort -g )
nb_lon=$(echo "$list_lon" | tr ' ' '\n' | wc -l | xargs)
max_lon=$(awk '{print $NF}' <<< $sort_lon)
min_lon=$(awk '{print $1}' <<< $sort_lon)

echo "curl -X GET \"http://router02.mapotempo.com/0.1/route.geojson?api_key=mapotempo-web-beta-d701e4a905fbd3c8d0600a2af433db8b&mode=crow&dimension=time&loc=$max_lat%2C%20$max_lon%2C%20$min_lat%2C%20$min_lon\""
curl=$(curl -X GET "http://router02.mapotempo.com/0.1/route.geojson?api_key=mapotempo-web-beta-d701e4a905fbd3c8d0600a2af433db8b&mode=crow&dimension=time&loc=$max_lat%2C%20$max_lon%2C%20$min_lat%2C%20$min_lon")

distance=$(jq '.features[] | .properties.router.total_distance' <<< $curl | awk -F '.' '{print $1}')
echo "Matrice $nb_lat x $nb_lon ($(($distance / 1000)) km); Coordonnées diagonale : $max_lat, $max_lon, $min_lat, $min_lon"

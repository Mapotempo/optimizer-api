#!/bin/bash

# $1 : nombre de jours à retirer du jour en cours
# $2 : serveur : beta ou prod
# $3 : le channel slack
# $4 : le chemin vers les logs api (access et passenger)
# $5 : le chemin vers les logs resques

export SCRIPTS_PATH=/usr/local/sbin
ytd=$(date -d "$1 day ago" +%d\ %b)
ytdgrep=$(date -d "$1 day ago" +'%Y-%m-%d')
optim_submit=$(zgrep -P "$ytdgrep.*POST.+submit" "$4" | wc -l)
optim_submit_sync=$(zgrep -P "$ytdgrep.*POST.+submit[^\"]+\" 200 " "$4" | wc -l)
optim_submit_async=$(zgrep -P "$ytdgrep.*POST.+submit[^\"]+\" 201 " "$4" | wc -l)

optim_submit_bad_request=$(zgrep -P "$ytdgrep.*POST.+submit[^\"]+\" 400 " "$4" | wc -l)
optim_submit_unauthorized=$(zgrep -P "$ytdgrep.*POST.+submit[^\"]+\" 401 " "$4" | wc -l)
optim_submit_expired=$(zgrep -P "$ytdgrep.*POST.+submit[^\"]+\" 402 " "$4" | wc -l)
optim_submit_limited=$(zgrep -P "$ytdgrep.*POST.+submit[^\"]+\" 413 " "$4" | wc -l)

optim_submit_error=$(zgrep -P "$ytdgrep.*POST.+submit[^\"]+\" 500 " "$4" | wc -l)

optim_accepted=$((optim_submit_async + optim_submit_sync))
optim_refused=$((optim_submit_bad_request + optim_submit_unauthorized + optim_submit_expired + optim_submit_limited))

optim_get=$(zgrep -P "$ytdgrep.*GET.+jobs" "$4" | wc -l)
optim_get_successful=$(zgrep -P "$ytdgrep.*GET.+jobs[^\"]+\" 200 " "$4" | wc -l)
optim_get_unauthorized=$(zgrep -P "$ytdgrep.*GET.+jobs[^\"]+\" 401 " "$4" | wc -l)
optim_get_not_found=$(zgrep -P "$ytdgrep.*GET.+jobs[^\"]+\" 404 " "$4" | wc -l)
optim_get_error=$(zgrep -P "$ytdgrep.*GET.+jobs[^\"]+\" 500 " "$4" | wc -l)

optim_delete=$(zgrep -P "$ytdgrep.*DELETE.+jobs" "$4" | wc -l)
optim_delete_successful=$(zgrep -P "$ytdgrep.*DELETE.+jobs[^\"]+\" 202 " "$4" | wc -l)
optim_delete_unauthorized=$(zgrep -P "$ytdgrep.*DELETE.+jobs[^\"]+\" 401 " "$4" | wc -l)
optim_delete_not_found=$(zgrep -P "$ytdgrep.*DELETE.+jobs[^\"]+\" 404 " "$4" | wc -l)
optim_delete_error=$(zgrep -P "$ytdgrep.*DELETE.+jobs[^\"]+\" 500 " "$4" | wc -l)

optim_sync_fatal=$(zgrep "$ytdgrep FATAL" "$4" | wc -l)
# shellcheck disable=SC2086
optim_async_started=$(zgrep -P "$ytdgrep.*Starting job" $5 | wc -l)
# shellcheck disable=SC2086
optim_async_ended=$(zgrep "$ytdgrep.*Elapsed time:" $5 | wc -l)
# shellcheck disable=SC2086
optim_async_canceled=$(zgrep "$ytdgrep.*Job Killed" $5 | wc -l)
# shellcheck disable=SC2086
optim_async_fatal=$(zgrep "$ytdgrep.*FATAL" $5 | wc -l)

optim_sync_ended=$((optim_submit_sync - optim_sync_fatal))
optim_still_running=$((optim_async_started - optim_async_fatal - optim_async_ended - optim_async_canceled))
optim_queued=$((optim_submit_async - optim_async_started))

echo "nombre de POST : $optim_submit"
echo "nombre de POST acceptés : $optim_accepted"
echo "nombre de POST refusés : $optim_refused"
echo "nombre de POST en échec : $optim_submit_error"
echo "Vérification POST (doit être égal à 0) : $((optim_submit - optim_submit_error - optim_refused - optim_accepted))"

echo "nombre de GET : $optim_get"
echo "nombre de GET réussis: $optim_get_successful"
echo "nombre de GET inconnus: $optim_get_not_found"
echo "nombre de GET non autorisés: $optim_get_unauthorized"
echo "nombre de GET en échec: $optim_get_error"
echo "Vérification GET (doit être égal à 0) : $((optim_get - optim_get_successful - optim_get_not_found - optim_get_error - optim_get_unauthorized))"

echo "nombre de DELETE : $optim_delete"
echo "nombre de DELETE réussis: $optim_delete_successful"
echo "nombre de DELETE inconnus: $optim_delete_not_found"
echo "nombre de DELETE non autorisés: $optim_delete_unauthorized"
echo "nombre de DELETE en échec: $optim_delete_error"
echo "Vérification DELETE (doit être égal à 0) : $((optim_delete - optim_delete_successful - optim_delete_not_found - optim_delete_error - optim_delete_unauthorized))"

echo "nombre d'optims asynchrones : $optim_submit_async"
echo "nombre d'optims asynchrones débutées : $optim_async_started"
echo "nombre d'optims asynchrones achevées : $optim_async_ended"
echo "nombre d'optims asynchrones annulées : $optim_async_canceled"
echo "nombre d'optims toujours en cours : $optim_still_running"

echo "nombre d'optims synchrones : $optim_submit_sync"
echo "nombre de ko : $optim_async_fatal"

######## async
# shellcheck disable=SC2207 disable=SC2086
declare -a val=($(zgrep "$ytdgrep.*Elapsed time:" $5 | grep -Po "\d{1,}\.\d{1,}s Vrp" | grep -Po "\d{1,}\.\d{1,}"))
total_async=0
min_async=0
max_async=0
for index in "${!val[@]}"
do
  echo "${val[$index]}"
  total_async=$(echo $total_async+"${val[$index]}" | bc)
  if [ "$min_async" == 0 ] || (( $(echo "${val[$index]}"'<'${min_async} | bc -l) )); then
    min_async=${val[$index]}
  fi
  if (( $(echo "${val[$index]}"'>'${max_async} | bc -l) )); then
    max_async=${val[$index]}
  fi
done
echo "min_async : $min_async"
echo "max_async : $max_async"
echo "total_async : $total_async"

echo "nb elapsed : ${#val[@]}"
avg_async=$(bc <<< "scale=2;$total_async/${#val[@]}")

############# sync
# shellcheck disable=SC2207
declare -a val=($(zgrep "$ytdgrep.*define_main_process elapsed" "$4" | grep -Po "\d+\.\d+ sec" | grep -Po "\d+\.\d+"))
total_sync=0
min_sync=0
max_sync=0
for index in "${!val[@]}"
do
  echo "${val[$index]}"
  total_sync=$(echo $total_sync+"${val[$index]}" | bc)
  if [ "$min_sync" == 0 ] || (( $(echo "${val[$index]}"'<'${min_sync} | bc -l) )); then
    min_sync=${val[$index]}
  fi
  if (( $(echo "${val[$index]}"'>'${max_sync} | bc -l) )); then
    max_sync=${val[$index]}
  fi
done
echo "min_sync : $min_sync"
echo "max_sync : $max_sync"
echo "total_sync : $total_sync"

echo "nb elapsed : ${#val[@]}"
avg_sync=$(bc <<< "scale=2;$total_sync/${#val[@]}")

message="*$2* $ytd VRP reçus(*$optim_submit*) : échecs($optim_submit_error), refusés(*$optim_refused*), acceptés($optim_accepted) -> sync($optim_submit_sync) & async($optim_submit_async)
  - Résolutions sync($optim_submit_sync) : échecs($optim_sync_fatal), terminées($optim_sync_ended), stats : min(${min_sync}s) moy(${avg_sync}s) max(${max_sync}s)
  - Résolutions async($optim_async_started) : échecs($optim_async_fatal), annulées($optim_async_canceled), en cours($optim_still_running), terminées($optim_async_ended), stats : min(${min_async}s) moy(${avg_async}s) max(${max_async}s)
Balance file d'attente : $optim_queued

GET($optim_get) : réussis($optim_get_successful), inconnus($optim_get_not_found), erreurs($optim_get_error), non autorisés($optim_get_unauthorized)
DELETE($optim_delete) : réussis($optim_delete_successful), inconnus($optim_delete_not_found), erreurs($optim_delete_error), non autorisés($optim_delete_unauthorized)
"

# shellcheck disable=SC1091
. ${SCRIPTS_PATH}/message-to-slack.sh -m "${message}" "xoxb-255521145702-jZ18ZgD6sJl1E2TO4ilB6itE" "$3"

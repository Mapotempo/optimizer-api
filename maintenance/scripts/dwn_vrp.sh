
#!/usr/bin/env bash
sha=$1
url=${2:-optimizer.beta.mapotempo.com}
file=$(ssh "$USER@$url" "ls /tmp/optimizer-api/dump/ | grep $sha")
name=$(sed 's/.*\(c[[:digit:]]*_.*\)_.*/\1/' <<< $file)

scp "$USER@$url:/tmp/optimizer-api/dump/$file" .
zlib-flate -uncompress < ./$file > ./$name # deflate
rm ./$file

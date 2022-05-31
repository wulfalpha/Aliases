#!/usr/bin/bash
echo "Nyan nyan" | lolcat
for i in {1..8}
do
    od -An -N8 -i < /dev/urandom | lolcat
done

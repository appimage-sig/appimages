#!/usr/bin/sh

find content/apps -type d '!' -exec sh -c 'ls -1 "{}" | grep -q "^metadata\.xml$"' ';' -print | sort > content/.nometada.txt

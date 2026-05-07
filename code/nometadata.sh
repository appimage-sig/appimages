#!/usr/bin/sh

find . -type d '!' -exec sh -c 'ls -1 "{}" | grep -q "metainfo.xml"' ';' -print | sort > content/.nometada.txt

#!/bin/bash

for file in *.el
do
    echo "Byte compile file: $file"
    expression="(byte-compile-file \""$file"\")"    
    emacs -no-site-file -no-init-file -batch -eval "$expression"
    echo
done

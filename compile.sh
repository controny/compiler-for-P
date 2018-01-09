#!/bin/bash

basename=`basename $1`
pname=${basename%.p}

mkdir -p temp
cd temp
../bin/parser ../$1 | tee parser.out
cd -
# Only if parser did not report error then continues compiling
if [[ `grep '<Error>' temp/parser.out | wc -l` == 0 ]]; then
	java -jar lib/jasmin.jar temp/"$pname.j"
fi

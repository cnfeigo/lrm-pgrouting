#!/bin/bash

VERSION=`echo "console.log(require('./package.json').version)" | node`

echo Building dist files for $VERSION...
mkdir -p dist
browserify -t browserify-shim src/L.Routing.PgRouting.js >dist/lrm-pgrouting.js
uglifyjs dist/lrm-pgrouting.js >dist/lrm-pgrouting.min.js
echo Done.

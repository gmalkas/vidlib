#!/usr/bin/env bash

shopt -s expand_aliases

alias esbuild=node_modules/.bin/esbuild
alias postcss=node_modules/.bin/postcss

TARGET_ENV="${1:-dev}"

case $TARGET_ENV in
  dev|development)
    ENV=development
    ESBUILD_OPTS=--sourcemap;;
  stg|staging)
    ENV=staging
    ESBUILD_OPTS="--minify --sourcemap";;
  prd|prod|production)
    ENV=production
    ESBUILD_OPTS="--minify --sourcemap";;
  *)
    echo "Please specify the environment."
    exit 1;
esac

function bundle_static() {
  echo -n "Copying static/..."
  mkdir -p ../priv
  cp -r static ../priv
  echo "done!"
}

function bundle_css() {
  echo -n "Bundling CSS..."
  postcss css/app.css -o ../priv/static/assets/app.css
  echo "done!"
}

function bundle_js() {
  echo -n "Bundling JS/TS..."
  esbuild --log-level=warning --color=true \
    --bundle --loader:.ts=ts --loader:.tsx=tsx --loader:.js=jsx js/app.js \
    --outfile=../priv/static/assets/app.js $ESBUILD_OPTS
  echo "done!"
}

function bundle() {
  bundle_static
  bundle_js
  bundle_css
}

if [ "$2" = "--watch" ]; then
  TAILWIND_MODE=build bundle

  selfpid=$$

  if [[ $OSTYPE =~ ^darwin ]]; then
    fswatch --batch-marker=EOF -xn ./js | while read file event; do
      if [ $file = "EOF" ]; then
        bundle_js
        TAILWIND_MODE=build bundle_css
      fi
    done

    fswatch --batch-marker=EOF -xn ./css | while read file event; do
      if [ $file = "EOF" ]; then
        TAILWIND_MODE=build bundle_css
      fi
    done

    fswatch --batch-marker=EOF -xn ./static | while read file event; do
      if [ $file = "EOF" ]; then
        bundle_static
      fi
    done
  else
    exec 0<&0 $(
      while read; do :; done
      kill -KILL $selfpid
    ) &

    while [ true ]; do
      CHANGED=$(inotifywait -qre modify js css static vendor ../lib/vidlib_web/templates ../lib/vidlib_web/live)
      TAILWIND_MODE=build bundle_css

      if [[ $CHANGED == js/* ]]; then
        bundle_js
      fi

      if [[ $CHANGED == static/* ]]; then
        bundle_static
      fi
    done
  fi
else
  set -e

  bundle
fi

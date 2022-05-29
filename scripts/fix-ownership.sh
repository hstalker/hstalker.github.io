#!/usr/bin/env sh

main() {
  pwd
  sudo rm ./.jekyll-metadata
  sudo chown -R $USER:$USER ./
}

main $@

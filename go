#!/bin/bash -e

export BUNDLE_GEMFILE="$(pwd)/conf/Gemfile"
export RAKEFILE="$(pwd)/lib/rakefile.rb"

# install gems using bundler
sudo yum install rubygems
gem list | grep bundler  || gem install bundler --version 1.0.21 --no-rdoc --no-ri

bundle exec rake -f $RAKEFILE $@


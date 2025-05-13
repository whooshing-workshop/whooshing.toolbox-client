#!/bin/bash

set -e

sources="Client/Sources"
targetSources="Client+Vapor/Sources"

tests="Client/Tests"
targetTests="Client+Vapor/Tests"

exclude="VaporDependencies"

rm -rf $targetSources $targetTests
mkdir -p $targetSources
mkdir -p $targetTests

./__sync.sh $sources $targetSources $exclude
./__sync.sh $tests $targetTests $exclude

#!/bin/bash
# ugly solution but it works
git add .
git commit -m $1
git push -u origin master
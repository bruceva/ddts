#!/bin/bash
grep "def " $1 | awk '{n=split($2,a,"("); print a[1]}'

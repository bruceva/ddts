#!/bin/bash

function listpreprocessors {
  grep ^preprocessors ../runs/* | awk -F ':' '
{
  n=split($3,procs,","); 
  for (i = 1; i <= n; i++) {
    gsub(/[ \t\[\],'\'']/,"",procs[i]) 
    procs_avail[procs[i]]++
  }
}
END {
 a=""
 for (proc in procs_avail)
   a=a" "proc 
 print a
}
'
}

function usage {
 echo "Usage: $1 <preprocessor|all> <filemask|blank>"
 echo "1st argument= a proprocessor name or all for the default behavior"
 echo "2nd argument= a filter for the files. leaving blank defaults to *"
 echo "ex: $1 all intel" 
 echo "    $1 all gfortran" 
 echo "    $1 wrf 3ice*intel" 
 echo "Available preprocessors: " 
 listpreprocessors
}

mask="r_*"
if [ x"$2" != x ] ; then
  mask="r_*$2*"
fi

if [ x"$1" == x ] ; then
  usage $0
elif [ x"$1" != "xall" ] ; then
  grep ^preprocessors ../runs/$mask | grep $1 | awk -v x=$1 -F ':' '
  BEGIN { 
    print "ddts_extends: email_nuwrf "
    print "ddts_continue: true";
    print "ddts_retain_builds: true";
  } 
  {
    n=split($1,a,"/")
    print "group"NR":"
    print "  - "a[n]"/"$2"=!replace [\x27"x"\x27]"
  } 
  END {
    print "#end"
  }'
else
  grep ^preprocessors ../runs/$mask | awk  -F ':' '
  BEGIN {
    print "ddts_extends: email_nuwrf "
    print "ddts_continue: true"
    print "ddts_retain_builds: true"
  } 
  {
    n=split($1,a,"/")
    print "group"NR":"
    print "  - "a[n]
  }
  END {
    print "#end"
  }'
fi

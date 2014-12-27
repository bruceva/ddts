#!/bin/bash
#
# NASA code 606
# This script downloads/updates the DDTS framework and nuwrf regression test repository 
# It also setups up the sandbox for the specified software suite
#
# Requires:
# Git version 1.8.5.2 or better -- due to improved network communication
# jruby 1.7.9 jar file. 
#
# History:
# April 11, 2014 - Eduardo G. Valente Jr. - created
#

if [ "$1" == "" ] ; then
  echo "This script creates the necessary directories and links to the supported suites in order to create a regression testing enviroment"
  echo "Usage: $0 ldt_suite|nuwrf_suite|repo_only"
  exit 0
elif [ "$1" != "ldt_suite" ] &&  [ "$1" != "nuwrf_suite" ] && [ "$1" != "repo_only" ] ; then
  echo "Suite not supporte"d
  exit 1
fi 

topdir=`pwd`

jrubyjar="$topdir/jruby-complete-1.7.9.jar"
java -jar $jrubyjar --version  || exit 1

gitexe="/usr/local/other/SLES11.1/git/1.8.5.2/libexec/git-core/git"
$gitexe --version || exit 1

#Install/Update user application source:
usergitname="ddts-user"
localusergit="$topdir/$usergitname"
remoteusergit="git://github.com/egvalentejr/ddts.git"

if [ -d $localusergit ] ; then
  cd "$localusergit"
  $gitexe status > "$topdir/gituser.txt"
  if [ "$?" -ne 0 ] ; then
    echo "Error: git status"
  else
    check=`grep "branch is up-to-date" "$topdir/gituser.txt" | wc -l`
    if [ "$check" -eq 1 ] ; then
      echo "Performing a user git pull"
      $gitexe pull
    else
      echo "Warning: Not performing user git pull"
      cat "$topdir/gituser.txt"
    fi
  fi
  rm "$topdir/gituser.txt"
  cd "$topdir"
else
  echo $localusergit does not exist
  $gitexe clone $remoteusergit $usergitname || exit 1
  cd "$localusergit"
  $gitexe checkout nuwrf
  cd $topdir
fi


#Install/Update core application source:
coregitname="ddts-core"
localcoregit="$topdir/$coregitname"
remotecoregit="git://github.com/maddenp/ddts.git"

if [ -d "$localcoregit" ] ; then
  cd "$localcoregit"
  $gitexe status > "$topdir/gitcore.txt"
  if [ "$?" -ne 0 ] ; then
    echo "Error: git status"
  else
    check=`grep "branch is up-to-date" "$topdir/gitcore.txt" | wc -l`
    if [ "$check" -eq 1 ] ; then
      echo "Performing a core git pull"
      $gitexe pull
    else
      echo "Warning: Not performing core git pull"
      cat "$topdir/gitcore.txt"
    fi
  fi
  rm "$topdir/gitcore.txt"
  cd "$topdir"
else
  echo $localcoregit does not exist
  $gitexe clone $remotecoregit $coregitname 
  cd "$localcoregit" || exit 1
  if [ -f "$localusergit/regts" ] ; then
    #Create link to special regts script that runs the regression testing
    ln -v -s "$localusergit/regts" || exit 1
  else
    echo "Warning: unable to locate required regts in user git" 
  fi
  if [ ! -f "jruby-complete.jar" ] ; then
    #Create link to the jruby jar file 
    ln -v -s "$jrubyjar" jruby-complete.jar
  fi
  cd "$topdir"  
fi

suite="nuwrf_suite"
if [ "$1" == "$suite" ] ; then
  #Create suite sandbox
  app="nuwrf_r_cases"
  appdir="$localusergit/$app"

  #Sanity check
  if [ ! -d $appdir ] ; then
    echo "Error: required directory $appdir not found"
    exit 1
  fi

  if [ ! -d "$topdir/$suite" ] ; then
    echo "Setting up $suite directory"
    mkdir "$topdir/$suite" || exit 1        
  else
    echo "$suite already installed"
  fi

  #Create application sandbox
  if [ ! -d "$topdir/$suite/$app" ] ; then
    echo "Setting up $app application sandbox"
    mkdir "$topdir/$suite/$app" || exit 1
    cd "$topdir/$suite/$app" || exit 1
    ln -s "$appdir" app
    ln -s "$localcoregit/regts"  
  else
    echo "Application $app already installed"
  fi
fi

suite="ldt_suite"
if [ "$1" == "$suite" ] ; then
  #Create suite sandbox
  app="ldt"
  appdir="$localusergit/$app"

  #Sanity check
  if [ ! -d $appdir ] ; then
    echo "Error: required directory $appdir not found"
    exit 1
  fi

  if [ ! -d "$topdir/$suite" ] ; then
    echo "Setting up $suite directory"
    mkdir "$topdir/$suite" || exit 1
  else
    echo "$suite already installed"
  fi

  #Create application sandbox
  if [ ! -d "$topdir/$suite/$app" ] ; then
    echo "Setting up $app application sandbox"
    mkdir "$topdir/$suite/$app" || exit 1
    cd "$topdir/$suite/$app" || exit 1
    ln -s "$appdir" app
    ln -s "$localcoregit/regts"
  else
    echo "Application $app already installed"
  fi
fi



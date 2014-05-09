#!/bin/sh
#SBATCH -J rip
#SBATCH -N 1 -n 1 --ntasks-per-node=1
#SBATCH -t 6:00:00
#SBATCH -A s0942
#SBATCH -o rip.slurm.out
#SBATCH -p general
#------------------------------------------------------------------------------
# NASA/GSFC, Software Systems Support Office, Code 610.3
#------------------------------------------------------------------------------
#                                                                              
# SCRIPT:  run_rip.discover.sh
#                                                                              
# AUTHOR:                                                                      
# Eric Kemp, NASA SSSO/SSAI
#                                                                              
# DESCRIPTION:                                                                 
# Sample script for running rip on the NASA GSFC Discover 
# supercomputer with SLURM.
#
#------------------------------------------------------------------------------

# When a batch script is started, it starts in the user's home directory.
# Change to the directory where job was submitted.
if [ ! -z $SLURM_SUBMIT_DIR ] ; then
    cd $SLURM_SUBMIT_DIR || exit 1
fi

# Load config file for modules and paths
source ./config.discover.sh || exit 1

# Go to work directory
if [ -z "$WORKDIR" ] ; then
    echo "ERROR, WORKDIR is not defined!"
    exit 1
fi
cd $WORKDIR || exit 1

# Copy rip and rip preprocessor to work directory.
if [ -z "$RIP_ROOT" ] ; then
    echo "ERROR, RIP_ROOT is not defined!"
    exit 1
fi
ln -fs $RIP_ROOT/ripdp_wrfarw ripdp_wrfarw || exit 1
if [ ! -e ripdp_wrfarw ] ; then
    echo "ERROR, ripdp_wrfarw does not exist!"
    exit 1
fi
ln -fs $RIP_ROOT/rip rip || exit 1
if [ ! -e rip ] ; then
    echo "ERROR, rip does not exist!"
    exit 1
fi

# List of "rip execution names" for defining namelist files.
ripfiles="200 250 300 500Vort 700RH 850 sfcThk sfcTUV COMDBZ sfcDBZUV"

# Link the rip input files
if [ -z "$NUWRFDIR" ] ; then
    echo "ERROR, NUWRFDIR is not defined!"
    exit 1
fi
for ripfile in $ripfiles ; do

    ln -fs $NUWRFDIR/scripts/rip/${ripfile}.in ${ripfile}.in || exit 1
    if [ ! -e ${ripfile}.in ] ; then
	echo "ERROR, ${ripfile}.in not found!"
	exit 1
    fi
done

# Process each domain
for domain in d01 d02 d03 d04 ; do

    # Count files, and exit for look if no files are found for current domain.
    count=`ls -x -1 | grep wrfout_${domain} | wc -l`

    if [ $count -eq 0 ] ; then
	break
    fi

    # Run preprocessor on current domain wrfout files
    files=`ls wrfout_${domain}_*_00:* wrfout_${domain}_*_03:* \
              wrfout_${domain}_*_06:* wrfout_${domain}_*_09:* \
              wrfout_${domain}_*_12:* wrfout_${domain}_*_15:* \
              wrfout_${domain}_*_18:* wrfout_${domain}_*_21:*`
    ./ripdp_wrfarw nuwrf_${domain} all $files || exit 1

    # Now run rip for each rip-execution-name.  Rename the cgm file to
    # prevent overwrites when processing a different domain.
    for ripfile in $ripfiles ; do
	./rip -f nuwrf_${domain} $ripfile || exit 1
	mv ${ripfile}.cgm ${ripfile}_${domain}.cgm || exit 1
    done
done

# The end
exit 0


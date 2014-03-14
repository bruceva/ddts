#!/bin/sh
#SBATCH -J geogrid
#SBATCH -t 0:01:00
#SBATCH -A s0942
#SBATCH -o geogrid.slurm.out
#SBATCH -p general
#SBATCH -N 24 -n 288 --ntasks-per-node=12 --constraint=west
##SBATCH -N 18 -n 288 --ntasks-per-node=16 --constraint=sand
#------------------------------------------------------------------------------
# NASA/GSFC, Software Systems Support Office, Code 610.3
#------------------------------------------------------------------------------
#                                                                              
# SCRIPT:  run_geogrid.discover.sh
#                                                                              
# AUTHOR:                                                                      
# Eric Kemp, NASA SSSO/SSAI
#                                                                              
# DESCRIPTION:                                                                 
# Sample script for running geogrid.exe on the NASA GSFC Discover 
# supercomputer with SLURM.
#
#------------------------------------------------------------------------------

# Change to the directory where job was submitted.
if [ ! -z $SLURM_SUBMIT_DIR ] ; then
    cd $SLURM_SUBMIT_DIR || exit 1
fi

# Load config file for modules and paths
source ./config.discover.sh || exit 1

# Move to work directory and make sure namelist.wps is present.
if [ -z "$WORKDIR" ] ; then
    echo "ERROR, WORKDIR is not defined!"
    exit 1
fi
cd $WORKDIR || exit 1
if [ ! -e namelist.wps ] ; then
    echo "ERROR, namelist.wps not found!"
    exit 1
fi

# Put geogrid TBL look-up file into geogrid subdirectory
if [ -z "$NUWRFDIR" ] ; then
    echo "ERROR, NUWRFDIR is not defined!"
    exit 1
fi
if [ -e geogrid ] ; then
    rm -rf geogrid || exit 1
fi
mkdir geogrid || exit 1

# Typical case: No chemistry
#ln -fs $NUWRFDIR/WPS/geogrid/GEOGRID.TBL.ARW geogrid/GEOGRID.TBL || exit 1

# Special case: Run with chemistry
#ln -fs $NUWRFDIR/WPS/geogrid/GEOGRID.TBL.ARW_CHEM geogrid/GEOGRID.TBL || exit 1

# Very special case: Run with chemistry and seasonal EROD (specific to NU-WRF)
ln -fs $NUWRFDIR/WPS/geogrid/GEOGRID.TBL.ARW_CHEM_GINOUX \
       geogrid/GEOGRID.TBL || exit 1

if [ ! -e geogrid/GEOGRID.TBL ] ; then 
    echo "ERROR, geogrid/GEOGRID.TBL does not exist!"
    exit 1
fi

# Run geogrid.exe
ln -fs $NUWRFDIR/WPS/geogrid/src/geogrid.exe geogrid.exe || exit 1
if [ ! -e geogrid.exe ] ; then 
    echo "ERROR, geogrid.exe does not exist!"
    exit 1
fi
mpirun -np $SLURM_NTASKS ./geogrid.exe || exit 1

# The end
exit 0


#!/bin/sh
#SBATCH -J ungrib
#SBATCH -N 1 -n 1 --ntasks-per-node=1
#SBATCH -t 00:10:00
#SBATCH -A s0942
#SBATCH -o ungrib.slurm.out
#SBATCH -p general
#------------------------------------------------------------------------------
# NASA/GSFC, Software Systems Support Office, Code 610.3           
#------------------------------------------------------------------------------
#                                                                              
# SCRIPT:  run_ungrib.discover.sh
#
# AUTHOR:                                                                      
# Eric Kemp, NASA SSSO/SSAI
#                                                                              
# DESCRIPTION:                                                                 
# Sample batch script for running ungrib.exe on NASA GSFC Discover 
# supercomputer with SLURM.
#
#------------------------------------------------------------------------------

# When a batch script is started, it starts in the user's home directory.
# Change to the directory where job was submitted.
if [ ! -z $SLURM_SUBMIT_DIR ] ; then
    cd $SLURM_SUBMIT_DIR || exit 1
fi

# Load config file for modules and paths.
source ./config.discover.sh || exit 1

# Go to work directory and make sure namelist.wps is present.
if [ -z "$WORKDIR" ] ; then
    echo "ERROR, WORKDIR is not defined!"
    exit 1
fi
cd $WORKDIR || exit 1
if [ ! -e namelist.wps ] ; then
    echo "ERROR, namelist.wps not found!"
    exit 1
fi

# Make sure Vtable is present.
# NOTE:  User may need to change source Vtable name depending on their data
# source.
if [ -z "$NUWRFDIR" ] ; then
    echo "ERROR, NUWRFDIR is not defined!"
    exit 1
fi
if [ -e Vtable ] ; then
    rm -f Vtable || exit 1
fi
ln -fs $NUWRFDIR/WPS/ungrib/Variable_Tables/Vtable.GFS Vtable || exit 1
#ln -fs $NUWRFDIR/WPS/ungrib/Variable_Tables/Vtable.AWIP Vtable || exit 1
#ln -fs $NUWRFDIR/WPS/ungrib/Variable_Tables/Vtable.NAM Vtable || exit 1
#ln -fs $NUWRFDIR/WPS/ungrib/Variable_Tables/Vtable.NARR Vtable || exit 1
if [ ! -e Vtable ] ; then
    echo "ERROR, Vtable does not exist!"
    exit 1
fi

# Create GRIBFILE symbolic links to grib files.
# NOTE:  User may need to change the grib file prefix depending on their
# data source.
ln -fs $NUWRFDIR/WPS/link_grib.csh link_grib.csh || exit 1
if [ ! -e link_grib.csh ] ; then
    echo "ERROR, link_grib.csh does not exist!"
    exit 1
fi
./link_grib.csh fnl_* || exit 1
#./link_grib.csh JAN00/2000012 || exit 1
#./link_grib.csh gfs_* || exit 1
#./link_grib.csh nam.* || exit 1
#./link_grib.csh narr-a* || exit 1

# Run ungrib.exe.  No MPI is used since the program is serial.
ln -fs $NUWRFDIR/WPS/ungrib/src/ungrib.exe ungrib.exe || exit 1
if [ ! -e ungrib.exe ] ; then
    echo "ERROR, ungrib.exe does not exist!"
    exit 1
fi

./ungrib.exe >& ungrib_data.log || exit 1

# The end
exit 0

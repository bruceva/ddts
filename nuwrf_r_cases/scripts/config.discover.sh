#!/bin/sh
#------------------------------------------------------------------------------
# NASA/GSFC, Software Systems Support Office, Code 610.3
#------------------------------------------------------------------------------
#                                                                              
# SCRIPT:  config.discover.sh
#                                                                              
# AUTHOR:                                                                      
# Eric Kemp, NASA SSSO/SSAI
#                                                                              
# DESCRIPTION:                                                                 
# Sample config file for running NU-WRF batch scripts on NASA GSFC Discover
# supercomputer.
#
#------------------------------------------------------------------------------

# We completely purge the module environment variables and LD_LIBRARY_PATH 
# before loading only those specific variables that we need.
source /usr/share/modules/init/sh 
module purge

unset LD_LIBRARY_PATH

module load comp/intel-13.0.1.117
module load mpi/impi-4.0.3.008
#module load other/comp/gcc-4.8.1
#module load other/mpi/openmpi/1.7.2-gcc-4.8.1-shared

export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/lib64

# Define locations of LIS, NUWRF, and the experiment work directory
LISDIR=/discover/nobackup/projects/lis
NUWRFDIR=/discover/nobackup/emkemp/NUWRF/svn/trunk_chem
WORKDIR=/discover/nobackup/emkemp/NUWRF/cases/R_EROD

# Set environment variables needed by RIP
export RIP_ROOT=$NUWRFDIR/RIP4
export NCARG_ROOT=/usr/local/other/SLES11.1/ncarg/6.0.0/intel-13.0.1.117
#export NCARG_ROOT=/usr/local/other/SLES11.1/ncarg/6.0.0/gnu-4.8.1

# Make sure stacksize is unlimited
ulimit -s unlimited


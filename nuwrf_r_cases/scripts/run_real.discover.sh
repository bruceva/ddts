#!/bin/sh
#SBATCH -J real
#SBATCH -t 1:00:00
#SBATCH -A s0942
#SBATCH -o real.slurm.out
#SBATCH -p general_hi
#SBATCH -N 24 -n 288 --ntasks-per-node=12 --constraint=west
##SBATCH -N 18 -n 288 --ntasks-per-node=16 --constraint=sand
#------------------------------------------------------------------------------
# NASA/GSFC, Software Systems Support Office, Code 610.3
#------------------------------------------------------------------------------
#                                                                              
# SCRIPT:  run_real.discover.sh
#                                                                              
# AUTHOR:                                                                      
# Eric Kemp, NASA SSSO/SSAI
#                                                                              
# DESCRIPTION:                                                                 
# Sample script for running real.exe on the NASA GSFC Discover 
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

# Move to work directory and make sure namelist.input is present.
if [ -z "$WORKDIR" ] ; then
    echo "ERROR, WORKDIR is not defined!"
    exit 1
fi
cd $WORKDIR || exit 1
if [ ! -e namelist.input ] ; then
    echo "ERROR, namelist.input not found!"
    exit 1
fi

# Copy the various wrf lookup files into the work directory.
if [ -z "$NUWRFDIR" ] ; then
    echo "ERROR, NUWRFDIR is not defined!"
    exit 1
fi
cd $NUWRFDIR/WRFV3/run || exit 1
for file in CAM_ABS_DATA CAM_AEROPT_DATA co2_trans ETAMPNEW_DATA \
            ETAMPNEW_DATA_DBL ETAMPNEW_DATA.expanded_rain \
            ETAMPNEW_DATA.expanded_rain_DBL GENPARM.TBL grib2map.tbl \
            gribmap.txt LANDUSE.TBL MPTABLE.TBL ozone.formatted \
            ozone_lat.formatted ozone_plev.formatted RRTM_DATA RRTM_DATA_DBL \
            RRTMG_LW_DATA RRTMG_LW_DATA_DBL RRTMG_SW_DATA RRTMG_SW_DATA_DBL \
            SOILPARM.TBL tr49t67 tr49t85 tr67t85 URBPARM.TBL URBPARM_UZE.TBL \
            VEGPARM.TBL ; do


    ln -fs $NUWRFDIR/WRFV3/run/$file $WORKDIR/$file || exit 1
    if [ ! -e $WORKDIR/$file ] ; then
	echo "ERROR, $file does not exist!"
	exit 1
    fi
done

# Run real.exe
ln -fs $NUWRFDIR/WRFV3/main/real.exe $WORKDIR/real.exe || exit 1
if [ ! -e $WORKDIR/real.exe ] ; then
    echo "ERROR, $WORKDIR/real.exe does not exist!"
    exit 1
fi
cd $WORKDIR || exit 1
mpirun -np $SLURM_NTASKS ./real.exe || exit 1

# Rename the various 'rsl' files to 'real.rsl'; this prevents wrf.exe from
# overwriting.
rsl_files=`ls rsl.*`
for file in $rsl_files ; do
    mv $file real.${file}
done

# The end
exit 0

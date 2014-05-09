#!/bin/sh
#SBATCH -J wrf
#SBATCH -t 12:00:00
#SBATCH -A s0942
#SBATCH -o wrf.slurm.out
#SBATCH -p general_hi
#SBATCH -N 24 -n 288 --ntasks-per-node=12 --constraint=west
##SBATCH -N 18 -n 288 --ntasks-per-node=16 --constraint=sand
#------------------------------------------------------------------------------
# NASA/GSFC, Software Systems Support Office, Code 610.3
#------------------------------------------------------------------------------
#                                                                              
# SCRIPT:  run_wrf.discover.sh
#                                                                              
# AUTHOR:                                                                      
# Eric Kemp, NASA SSSO/SSAI
#                                                                              
# DESCRIPTION:                                                                 
# Sample script for running wrf.exe on the NASA GSFC Discover supercomputer
# with SLURM.
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

    if [ ! -e $file ] ; then
        echo "ERROR, $file does not exist!"
        exit 1
    fi

    ln -fs $NUWRFDIR/WRFV3/run/$file $WORKDIR/$file || exit 1
    if [ ! -e $WORKDIR/$file ] ; then
	echo "ERROR, $WORKDIR/$file does not exist!"
	exit 1
    fi
done

# For running WRF/LIS. 
# FIXME: Add logic to skip this if uncoupled WRF will be run.
rm $WORKDIR/LS_PARAMETERS
rm $WORKDIR/MET_FORCING
ln -fs $LISDIR/LS_PARAMETERS $WORKDIR/LS_PARAMETERS || exit 1
if [ ! -e $WORKDIR/LS_PARAMETERS ] ; then
    echo "ERROR, $WORKDIR/LS_PARAMETERS does not exist!"
    exit 1
fi
ln -fs $LISDIR/MET_FORCING $WORKDIR/MET_FORCING || exit 1
if [ ! -e $WORKDIR/MET_FORCING ] ; then
    echo "ERROR, $WORKDIR/MET_FORCING does not exist!"
    exit 1
fi

# Link the wrf.exe executable
ln -fs $NUWRFDIR/WRFV3/main/wrf.exe $WORKDIR/wrf.exe || exit 1
if [ ! -e $WORKDIR/wrf.exe ] ; then
    echo "ERROR, $WORKDIR/wrf.exe does not exist!"
    exit 1
fi

# Run wrf.exe
cd $WORKDIR || exit 1
mpirun -np $SLURM_NTASKS ./wrf.exe || exit 1

# Rename the various 'rsl' files to 'wrf.rsl'; this prevents real.exe from
# overwriting.
rsl_files=`ls rsl.*`
for file in $rsl_files ; do
    mv $file wrf.${file}
done

# The end
exit 0


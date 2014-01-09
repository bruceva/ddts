#!/bin/bash
. /usr/share/modules/init/bash 
module purge
module load comp/intel-13.1.2.183 other/mpi/openmpi/1.7.2-intel-13.1.2.183
./tests   

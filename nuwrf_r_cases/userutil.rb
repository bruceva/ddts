require 'net/smtp'
require 'open3'

module UserUtil

  # *************************************************************
  # CUSTOM METHODS (NOT CALLED BY DRIVER)

  # Edit the lis.config file found in rundir according to the parameters
  # stored in the env data structure
  def modifyLisConfig(env,rundir)
    lisconfig=File.join(rundir,'lis.config')
    if File.exists?(lisconfig)
      logd "Special handling of lis.config file"
      # Edit processor along x value
      x=env.run.lis_config.send(env.run.proc_id).x if env.run.lis_config.class == OpenStruct
      cmd="sed -i -e 's/\\(Number of processors along x:\\)\\([ \\t]*\\)[0-9]*/\\1\\2"+x+"/g' "+lisconfig if x
      ext(cmd,{:msg=>"Editing x procs lis.config entry failed, see #{logfile}"})

      # Edit processor along y value
      y=env.run.lis_config.send(env.run.proc_id).y if env.run.lis_config.class == OpenStruct
      cmd="sed -i -e 's/\\(Number of processors along y:\\)\\([ \\t]*\\)[0-9]*/\\1\\2"+y+"/g' "+lisconfig if y
      ext(cmd,{:msg=>"Editing y procs lis.config entry failed, see #{logfile}"}) 
      
      #log changes
      cmd="grep processors "+lisconfig
      ext(cmd,{:msg=>"grep lis.config see #{logfile}"})
    else
      logw "Unable to find #{lisconfig} config file"
    end
  end 

  def pipe_ext(cmd,props={})

    # Execute a system command in a subshell, collecting stdout and stderr. If
    # property :die is true, die on a nonzero subshell exit status,printing the
    # message keyed by property :msg, if any. If property :out is true, write
    # the collected stdout/stderr to the delayed log.
    # Note: adding 2>&1 to cmd consolidates stderror and stdout

    d=(props.has_key?(:die))?(props[:die]):(true)
    m=(props.has_key?(:msg))?(props[:msg]):("")
    o=(props.has_key?(:out))?(props[:out]):(true)
    output=[]
    error=[]
    logi "Pipe ext: #{cmd}"
    status=nil
    sin,sout,serr,thr = Open3.popen3(cmd)
    # {|sin, sout, serr, thr|
    pid = thr[:pid]
    puts "HI"
    sout.read.each_line { |x| output.push(x) }
    serr.read.each_line { |x| error.push(x) }
    sin.close
    sout.close
    serr.close
    #}
    puts "HELLO"
    if o
      puts "* Output from #{cmd} (status code=#{status}):"
      puts "---- out< ----"
      output.each { |e| puts e }
      puts "---- >out ----"
      puts "---- error< ----"
      error.each { |e| puts e }
      puts "---- >error ----"
    end
    #die(m) if d and status!=0
    [output,status,error]
  end

  def my_ext(cmd,props={})

    # Execute a system command in a subshell, collecting stdout and stderr. If
    # property :die is true, die on a nonzero subshell exit status,printing the
    # message keyed by property :msg, if any. If property :out is true, write
    # the collected stdout/stderr to the delayed log.

    d=(props.has_key?(:die))?(props[:die]):(true)
    m=(props.has_key?(:msg))?(props[:msg]):("")
    o=(props.has_key?(:out))?(props[:out]):(true)
    output=[]
    IO.popen("#{cmd}") { |io| io.read.each_line { |x| output.push(x) } }
    status=$?.exitstatus
    if o
      logd "* Output from #{cmd} (status code=#{status}):"
      logd "---- 8< ----"
      output.each { |e| logd e }
      logd "---- >8 ----"
    end
    die(m) if d and status!=0
    [output,status]
  end

  def createBatchJobScript (env,rundir)
    
    walltime=env.run.wallTime
    name=env.run.batchName
    proc_id=env.run.proc_id

    #if proc_line was a hash we could dereference with [].  Since all hashes become OpenStruct, 
    #to dereference an OpenStruct without converting it to a hash first
    #use the Object.send() method
    procs=env.run.proc_line.send(proc_id) 
    numproc=env.run.procs_to_int.send(proc_id) 
    
    group=env.run.groupName
    loadModules=env.run.modules
    batchScript=<<-eos
#!/bin/bash
#PBS -S /bin/bash
#PBS -N #{name}
#PBS -l #{procs}
#PBS -l walltime=#{walltime}
## does not work:PBS -W group_list= use instead:
#SBATCH -A #{group}
#PBS -j eo

# environment setup
. /usr/share/modules/init/bash
module purge
module load #{loadModules} 

ulimit -s unlimited

# assumes job starts from the WRF run directory
cd #{rundir}
pwd
mpirun -np #{numproc} ./wrf.exe
exit 0
eos
    batchScript
  end

  def createCommonPreprocessorScript(env,rundir)

    loadModules=env.run.modules.send(env.run.compiler)
    batchExports=env.run.batch_exports.send(env.run.compiler)
  
    script=<<-eos
#!/bin/bash

# --- shared script used by specific preprocessor scripts ----

source /usr/share/modules/init/sh
module purge

unset LD_LIBRARY_PATH
module load #{loadModules}

export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/lib64

# Define locations of LIS, NUWRF, and the experiment work directory
LISDIR=#{env.run.lis_dir}
NUWRFDIR=#{env.build.dir}
WORKDIR=#{rundir}

# Make sure stacksize is unlimited
ulimit -s unlimited

# Set environment variables needed by RIP
export RIP_ROOT=$NUWRFDIR/RIP4
eos
    batchExports.each { |expo| script << "export #{expo}\n"}

    script
  end

  def lib_re_str_job_id
    '(\d+).*'
  end

  def lib_submit_script
    'qsub'
  end

  def batch_filename(env)
    "runWrf_#{env.run.proc_id}.job"
  end

  def createPreprocessorHeader(env, preprocessor)

    script="#!/bin/bash\n"
    script<<"#SBATCH -J #{env.run.batch_name.send(preprocessor)}\n"
    script<<"#SBATCH -t #{env.run.batch_time.send(preprocessor)}\n"
    script<<"#SBATCH -A #{env.run.batch_group.send(preprocessor)}\n"
    script<<"#SBATCH -o #{env.run.batch_slurmout.send(preprocessor)}\n"
    script<<"#SBATCH -p #{env.run.batch_queue.send(preprocessor)}\n"
    proclineid=env.run.batch_procline.send(preprocessor)
    script<<"#SBATCH -N #{env.run.proc_line.send(proclineid)}\n"
    script<<"\n#---------------------- #{preprocessor} script -----------------------------\n\n"  

    script
  end

  def createCommonPreprocessorBody(env,namelist=nil)

    script=<<-eos
# Change to the directory where job was submitted.
if [ ! -z $SLURM_SUBMIT_DIR ] ; then
    cd $SLURM_SUBMIT_DIR || exit 1
fi

# Load config file for modules and paths
source ./common.bash || exit 1

if [ -z "$NUWRFDIR" ] ; then
    echo "ERROR, NUWRFDIR is not defined!"
    exit 1
fi

# Move to work directory
if [ -z "$WORKDIR" ] ; then
    echo "ERROR, WORKDIR is not defined!"
    exit 1
fi

cd $WORKDIR || exit 1

eos

    if namelist

      script2=<<-eos
# make sure #{namelist} is present.
if [ ! -e #{namelist} ] ; then
    echo "ERROR, #{namelist} not found!"
    exit 1
fi

eos
      script+script2
    else
      script
    end
  end

  def createGeogridLinks(env)

    script=<<-eos
# Put geogrid TBL look-up file into geogrid subdirectory

if [ -e geogrid ] ; then
    rm -rf geogrid || exit 1
fi
mkdir geogrid || exit 1

eos
    links=env.run.preprocessor_links.send(env.run.geogrid_select)
    f=File.join('$NUWRFDIR','WPS','geogrid',links[0])
    l=File.join('geogrid',links[1])
    script<<"ln -fs #{f} #{l} || exit 1\n" 

    check=<<-eos
if [ ! -e geogrid/#{links[1]} ] ; then 
    echo "ERROR, geogrid/#{links[1]} does not exist!"
    exit 1
fi
eos
    script+check
  end

  def createGeogridPreprocessorScript(env)

    header=createPreprocessorHeader(env,'geogrid')
  
    body=createCommonPreprocessorBody(env,'namelist.wps')

    body<<createGeogridLinks(env)

    footer=<<-eos
# Run geogrid.exe
ln -fs $NUWRFDIR/WPS/geogrid/src/geogrid.exe geogrid.exe || exit 1
if [ ! -e geogrid.exe ] ; then 
    echo "ERROR, geogrid.exe does not exist!"
    exit 1
fi
mpirun -np $SLURM_NTASKS ./geogrid.exe || exit 1

# Tidy up logs
mkdir geogrid_logs || exit 1

mv geogrid.log.* geogrid_logs

# The end
exit 0
eos

    header+body+footer
  end

  def getUngribInputVtable(env)
    links=env.run.preprocessor_links.send(env.run.ungrib_select)
    links[0]
  end

  def getUngribInputVtableLink(env)
    links=env.run.preprocessor_links.send(env.run.ungrib_select)
    links[1]
  end

  def getUngribInputPattern(env)
    links=env.run.preprocessor_links.send(env.run.ungrib_select)
    links[2]
  end

  def createUngribLinks(env)

    l=getUngribInputVtableLink(env)

    script=<<-eos
# Make sure #{l} is present.
# NOTE:  User may need to change source #{l} name depending on their data
# source.

if [ -e #{l} ] ; then
    rm -f #{l} || exit 1
fi
eos

    f=File.join('$NUWRFDIR','WPS','ungrib','Variable_Tables',getUngribInputVtable(env))
    script<<"ln -fs #{f} #{l} || exit 1\n"
    
    check=<<-eos
if [ ! -e #{l} ] ; then 
    echo "ERROR, #{l} does not exist!"
    exit 1
fi
eos
    script<<check

    script2=<<-eos
# Create GRIBFILE symbolic links to grib files.
# NOTE:  User may need to change the grib file prefix depending on their
# data source.
ln -fs $NUWRFDIR/WPS/link_grib.csh link_grib.csh || exit 1
if [ ! -e link_grib.csh ] ; then
    echo "ERROR, link_grib.csh does not exist!"
    exit 1
fi

./link_grib.csh #{getUngribInputPattern(env)} || exit 1
eos

    script+script2
  end

  def createUngribPreprocessorScript(env)

    header=createPreprocessorHeader(env,'ungrib')

    body=createCommonPreprocessorBody(env,'namelist.wps')

    body<<createUngribLinks(env)

    footer=<<-eos
# Run ungrib.exe.  No MPI is used since the program is serial.
ln -fs $NUWRFDIR/WPS/ungrib/src/ungrib.exe ungrib.exe || exit 1
if [ ! -e ungrib.exe ] ; then
    echo "ERROR, ungrib.exe does not exist!"
    exit 1
fi

./ungrib.exe >& ungrib_out.log || exit 1

# Tidy up logs
mkdir ungrib_logs || exit 1

mv ungrib_out.log ungrib_logs
mv ungrib.log ungrib_logs

# The end
exit 0
eos

    header+body+footer
  end

  def createMetgridLinks(env)

    script=<<-eos
# Put metgrid TBL look-up file into metgrid subdirectory

if [ -e metgrid ] ; then
    rm -rf metgrid || exit 1
fi
mkdir metgrid || exit 1

eos
    links=env.run.preprocessor_links.send(env.run.metgrid_select)
    f=File.join('$NUWRFDIR','WPS','metgrid',links[0])
    l=File.join('metgrid',links[1])
    script<<"ln -fs #{f} #{l} || exit 1\n"

    check=<<-eos
if [ ! -e metgrid/#{links[1]} ] ; then 
    echo "ERROR, metgrid/#{links[1]} does not exist!"
    exit 1
fi
eos
    script+check
  end

  def createMetgridPreprocessorScript(env)

    header=createPreprocessorHeader(env,'metgrid')

    body=createCommonPreprocessorBody(env,'namelist.wps')

    body<<createMetgridLinks(env)

    footer=<<-eos
# Run metgrid.exe
ln -fs $NUWRFDIR/WPS/metgrid/src/metgrid.exe metgrid.exe || exit 1
if [ ! -e "metgrid.exe" ] ; then
    echo "ERROR, metgrid.exe does not exist!"
    exit 1
fi
mpirun -np $SLURM_NTASKS ./metgrid.exe || exit 1

# Tidy up logs
mkdir metgrid_logs || exit 1

mv metgrid.log.* metgrid_logs

# The end
exit 0
eos

    header+body+footer
  end

  def createRealLinks(env)

    script=""
    links=env.run.preprocessor_links.send(env.run.real_select)
    links.each do |l|
      fw=File.join('$WORKDIR',l)
      f=File.join('$NUWRFDIR','WRFV3','run',l)
      check=<<-eos
if [ ! -e #{f} ] ; then 
    echo "ERROR, #{f} does not exist!"
    exit 1
fi
eos
      script<<check
      script<<"ln -fs #{f} #{fw} || exit 1\n"
      
    end
    script
  end

  def createRealPreprocessorScript(env)

    header=createPreprocessorHeader(env,'real')

    body=createCommonPreprocessorBody(env,'namelist.input')

    body<<createRealLinks(env)

    footer=<<-eos

# Run real.exe
ln -fs $NUWRFDIR/WRFV3/main/real.exe $WORKDIR/real.exe || exit 1
if [ ! -e $WORKDIR/real.exe ] ; then
    echo "ERROR, $WORKDIR/real.exe does not exist!"
    exit 1
fi

mpirun -np $SLURM_NTASKS ./real.exe || exit 1

# Rename the various 'rsl' files to 'real.rsl'; this prevents wrf.exe from
# overwriting.
rsl_files=`ls rsl.*`
for file in $rsl_files ; do
    mv $file real.${file}
done

# Tidy up logs
mkdir real_logs || exit 1

mv real.rsl.* real_logs

# The end
exit 0
eos

    header+body+footer
  end

  def getPreprocessorScriptName(p)
    p+'.bash' 
  end

  def createWrfLinks(env)
    script=""
    if env.run.wrf_select and env.run.wrf_select.class == Array
      env.run.wrf_select.each do |type|
        script<<createWrfTypedLinks(env,type)
      end      
    elsif env.run.wrf_select
      script<<createWrfTypedLinks(env,env.run.wrf_select)
    end
    script
  end

  def createWrfTypedLinks(env,type)

    script=""

    if type.include?('wrf')
      links=env.run.preprocessor_links.send(type)
      links.each do |l|
        f=File.join('$NUWRFDIR','WRFV3','run',l)
        check=<<-eos
if [ ! -e #{f} ] ; then 
    echo "ERROR, #{f} does not exist!"
    exit 1
fi
eos
        script<<check
        script<<"ln -fs #{f} #{l} || exit 1\n"
      end
    elsif type.include?('lis')
      links=env.run.preprocessor_links.send(type)
      links.each do |l|
        fw=File.join('$WORKDIR',l)
        script<<"rm #{fw}\n"
        f=File.join('$LISDIR',l)
        check=<<-eos
if [ ! -e #{f} ] ; then 
    echo "ERROR, #{f} does not exist!"
    exit 1
fi  
eos
        script<<check
        script<<"ln -fs #{f} #{fw} || exit 1\n"
      end
    end
    script
  end

  def createWrfPreprocessorScript(env)

    header=createPreprocessorHeader(env,'wrf')

    body=createCommonPreprocessorBody(env,'namelist.input')

    body<<createWrfLinks(env)

    footer=<<-eos

# Run wrf.exe
ln -fs $NUWRFDIR/WRFV3/main/wrf.exe $WORKDIR/wrf.exe || exit 1
if [ ! -e $WORKDIR/wrf.exe ] ; then
    echo "ERROR, $WORKDIR/wrf.exe does not exist!"
    exit 1
fi

mpirun -np $SLURM_NTASKS ./wrf.exe || exit 1

# Rename the various 'rsl' files to 'wrf.rsl'; this prevents real.exe from
# overwriting.
rsl_files=`ls rsl.*`
for file in $rsl_files ; do
    mv $file wrf.${file}
done

# Tidy up logs
mkdir wrf_logs || exit 1

mv wrf.rsl.* wrf_logs

# The end
exit 0
eos

    header+body+footer
  end

  def createRipLinks(env)

    script=""
    links=env.run.preprocessor_links.send(env.run.rip_select)
    links.each do |l|
      fname=l+".in"
      fw=File.join('$WORKDIR',fname)
      f=File.join('$NUWRFDIR','scripts','rip',fname)
      check=<<-eos
if [ ! -e #{f} ] ; then 
    echo "ERROR, #{f} does not exist!"
    exit 1
fi
eos
      script<<check
      script<<"ln -fs #{f} #{fw} || exit 1\n"

    end
    script
  end

  def listRipNames(env)
    list=""
    links=env.run.preprocessor_links.send(env.run.rip_select)
    links.each do |l|
      list<<l+" "
    end
    list
  end

  def createRipPreprocessorScript(env)

    header=createPreprocessorHeader(env,'rip')

    body=createCommonPreprocessorBody(env)

    body<<createRipLinks(env)

    body<<"ripfiles=\"#{listRipNames(env)}\"\n"

    testphrase="We're outta here like Vladimir"

    footer=<<-eos

# Link rip and rip preprocessor to work directory.
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

# Process each domain
domain_total=0
domain_pass=0
for domain in d01 d02 d03 d04 ; do

    # Count files, and exit for look if no files are found for current domain.
    count=`ls -x -1 | grep wrfout_${domain} | wc -l`

    if [ $count -eq 0 ] ; then
        break
    fi

    let "domain_total = domain_total + 1"

    # Run preprocessor on current domain wrfout files
    files=`ls wrfout_${domain}_*_00:* wrfout_${domain}_*_03:* \
              wrfout_${domain}_*_06:* wrfout_${domain}_*_09:* \
              wrfout_${domain}_*_12:* wrfout_${domain}_*_15:* \
              wrfout_${domain}_*_18:* wrfout_${domain}_*_21:*`
    ./ripdp_wrfarw nuwrf_${domain} all $files || exit 1

    # Now run rip for each rip-execution-name.  Rename the cgm file to
    # prevent overwrites when processing a different domain.
    total=0
    pass=0
    for ripfile in $ripfiles ; do
        ./rip -f nuwrf_${domain} $ripfile || exit 1
        mv ${ripfile}.cgm ${ripfile}_${domain}.cgm || exit 1
        mv ${ripfile}.out ${ripfile}_${domain}.out || exit 1
        test=`grep "#{testphrase}" ${ripfile}_${domain}.out | wc -l`
        let "total = total + 1"
        if [ $test -eq 1 ] ; then
          let "pass = pass + 1"
        fi
    done
    if [ $total -eq $pass ] ; then
      let "domain_pass = domain_pass + 1"
    fi
    echo "${pass} out of ${total} rip charts succeeded for ${domain} domain" > rip_result_${domain}.out
    rm -fv nuwrf_${domain}_*.00000_* 
done

echo "${domain_pass} out of ${domain_total} domains succeeded" > rip_results.out
if [ $domain_total -eq $domain_pass ] ; then
  echo "Success" >> rip_results.out
fi

# Tidy up logs
mkdir rip_logs || exit 1

mv rip_result* rip_logs

# The end
exit 0
eos

    header+body+footer
  end



  def run_batch_job(env,rundir,preprocessor)
    jobid=nil
    re1=Regexp.new(lib_re_str_job_id)
    ss=lib_submit_script
    ss+=" #{getPreprocessorScriptName(preprocessor)}"
    cmd="cd #{rundir} && #{ss}"
    logd "Submitting job with command: #{cmd}"
    output,status=ext(cmd,{:msg=>"Job submission failed"})
    output.each do |e|
      e.chomp!
      logd e unless e=~/^\s*$/
      jobid=e.gsub(re1,'\1') if re1.match(e)
    end
    if jobid.nil?
      logi "ERROR: Job ID not found in #{ss} output"
      return nil
    end
    qs="Queued with job ID #{jobid}"
    logi qs
    job_activate(jobid,self)
    wait_for_job(jobid)
    job_deactivate(jobid)
    outfile=File.join(rundir,env.run.expectedStatusFiles.send(preprocessor)[0])
    if File.exists?(outfile)
      logd "#{outfile} found"
    else
      die("#{outfile} not found")
    end
    outfile
  end

  def wait_for_job(jobid)
    ok=%w[E H Q R T W S]
    # 'tolerance' is the number of seconds to continue trying qstat before deeming the job
    # to have finished 
    tolerance=30
    batch_failure=false
    last_response=Time.now
    state='X'
    begin
      sleep 10
      tolog=[]
      cmd="qstat -f #{jobid}"
      output,status=ext(cmd,{:die=>false,:out=>false})
      if status==0
        live=false
        last_response=Time.now
        output.each do |e|
          tolog.push(e)
          state=(e.chomp.sub(/ *job_state = (.) *$/,'\1')).strip
          if ok.include?(state)
            live=true
            logd "job state: #{state}"
          end
        end
      else
        live=true
        now=Time.now
        logd "#{cmd} set error status #{status} at #{now}"
        if now-last_response > tolerance
          live=false
        end
      end
    end while live
    logd "* Final batch info for job ID #{jobid}:"
    logd "--"
    tolog.each { |e| logd e }
    logd "--"
    state
  end
 
  def send_email(from,to,subject,server,body,include_log)

    marker= "alksjdhf7400297143627990123" #Used to separate sections of a multi-part email

    #Compose email header
    #'to' can be a single email string, a comma separated multi email strings, or a string array
    to_mod = nil
    if to.class == String
      to_mod = to.split(",").map { |x| "<#{x}>"}.join(",")
    else
      to_mod=to.map { |x| "<#{x}>" }.join(",")  if to.respond_to?('map')
    end

    header=<<EOF
From: #{from}
To: #{to_mod}
Subject: #{subject}
MIME-Version: 1.0
Content-Type: multipart/mixed; boundary=#{marker}

--#{marker}
EOF
    #Compose email body
    my_body=<<EOF
Content-Type: text/plain
Content-Transfer-Encoding:8bit

#{body}
EOF

    message=header + my_body

    if include_log
      #Compose Email attachment
      logfilename=logfile()
      logcontent=File.read(logfilename)
      encodedcontent = [logcontent].pack("m")  #base64 encoding
      attachment=<<EOF
Content-Type: multipart/mixed; name=\"#{logfilename}.txt\"
Content-Transfer-Encoding: base64
Content-Disposition: attachment; filename="#{logfilename}.txt"

#{encodedcontent}
EOF

      message+=("--#{marker}\n"+ attachment + "--#{marker}--\n")
    else
      message+="--#{marker}--\n"
    end

    begin
      f=File.open("#{logfilename}.txt","w")
      f.write(message)
    rescue IOError => e
    ensure
      f.close unless f == nil
    end

    to_array=nil
    if to.class == String
      to_array= to.split (",")
    else
      to_array= to.map { |x| x} if to.respond_to?('map')
    end
    to_array.each do |recipient|
      begin
        Net::SMTP.start(server) do |smtp|
          smtp.send_message message, from, recipient
        end
      rescue Exception => e
        logi "Email exception occurred: #{e}"
      end
    end
  end
  
end

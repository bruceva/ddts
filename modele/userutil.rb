require 'net/smtp'
require 'open3'

module UserUtil

  # REQUIRED METHODS (CALLED BY DRIVER)

  # *********************** WEEKLY build functions **************************
  def lib_outfiles_batch(env,path)
    logd "lib_outputfiles->path-> #{path}"
    env.run.expectedOutputFiles.map { |x| [path,x] }
    #Note must return list with [path,file] pairs or empty one 
  end

  def lib_queue_del_cmd_batch(env)
    'qdel'
  end

  # *************************************************************
  # CUSTOM METHODS (NOT CALLED BY DRIVER)
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

  def edit_I_file_for_25hr(f,cold_restart=false)

    dateendpattern="^[[:space:]]*YEARE=[0-9]\{4\},[[:space:]]*MONTHE=[0-9]\{1,2\},[[:space:]]*DATEE=[0-9]\{1,2\},[[:space:]]*HOURE=\{1,2\}.*"
    dateendcoldpattern="^[[:space:]]*ISTART=[0-9]\{1\},[[:space:]]*IRANDI=[0-9]*,[[:space:]]*YEARE=[0-9]\{4\},[[:space:]]*MONTHE=[0-9]\{1,2\},[[:space:]]*DATEE=[0-9]\{1,2\},[[:space:]]*HOURE=\{1,2\}.*"
    startparamspattern="^[[:space:]]*&&PARAMETERS.*"
    endparamspattern="^[[:space:]]*&&END_PARAMETERS.*"
    inputzpattern="^[[:space:]]*&INPUTZ[[:space:]]*$"
    inputzcoldpattern="^[[:space:]]*&INPUTZ_cold[[:space:]]*$"
    ndiskpattern="^[[:space:]]*Ndisk=[0-9]*$"
    re_dep=Regexp.new(dateendpattern)
    re_decp=Regexp.new(dateendcoldpattern)
    re_spp=Regexp.new(startparamspattern)
    re_epp=Regexp.new(endparamspattern)
    re_ip=Regexp.new(inputzpattern)
    re_icp=Regexp.new(inputzcoldpattern)
    re_ndp=Regexp.new(ndiskpattern)
    in_spp_block=false
    in_epp_block=false
    in_ip_block=false
    in_icp_block=false
    f_new=File.join(File.dirname(f),"I.new")
    FileUtils.rm(f_new) if File.exist?(f_new)
    f_orig=File.join(File.dirname(f),"I.orig")
    #die "Run failed: Could not find #{stdout}" unless File.exist?(stdout)
    File.open(f,"r") do |io|
      ofile=File.open(f_new,"w")
      io.readlines.each do |e|
        wrote_line=false 

        #state machine finds the parameters within the start and end parameters patterns
        #and parameters after the end parameters block
        if re_spp.match(e)
          in_spp_block=true
          in_epp_block=false
        elsif re_epp.match(e)
          in_spp_block=false
          in_epp_block=true  
        elsif re_ip.match(e)
          in_ip_block=true
          in_icp_block=false
        elsif re_icp.match(e)
          in_ip_block=false
          in_icp_block=true
        else
          if in_spp_block and re_ndp.match(e)
            v=get_value_cdstr(e,"Ndisk")
            r=set_value_cdstr(e,"Ndisk",48,false) #Ndisk is the number of half hour simulation intervals to wait before writing out a restart file.
            if r
              logd("Replaced Ndisk=#{v} line with Ndisk=48")
              ofile.write(r)
            else
              die("Unable to update I file's Ndisk parameter")
            end
            wrote_line=true
          elsif in_epp_block and in_ip_block and re_dep.match(e) and cold_restart==false
            v=get_value_cdstr(e,"HOURE")
            r=set_value_cdstr(e,"HOURE",v.to_i+1)
            if r
              logd("Replacing warm start line #{e}")
              logd("with line #{r}")
              ofile.write(r)
            else
              die("Unable to update I file warm restart DATEE")
            end 
            wrote_line=true
          elsif in_epp_block and in_icp_block and re_decp.match(e) and cold_restart==true
            v=get_value_cdstr(e,"DATEE")
            r=set_value_cdstr(e,"DATEE",v.to_i+1)
            if r
              logd("Replacing cold start line #{e}")
              logd("with line #{r}") 
              ofile.write(r)
            else
              die("Unable to update I file cold restart DATEE")
            end 
            wrote_line=true
          end
        end
        if not wrote_line
          #echo line back out since it is not of particular interest
          ofile.write(e)
        end 
      end
      ofile.close
    end
    if File.exist?(f_new)
      if not File.exist?(f_orig)
        FileUtils.mv(f,f_orig)
      else
        FileUtils.rm(f)
      end
      FileUtils.mv(f_new,f)
      true
    else
      false
    end
  end

  # Takes a comma delimited string of key=val pairs, locates the key and returns the value 
  def get_value_cdstr(line,keypattern)
    result=nil
    re=Regexp.new(keypattern)
    arr=line.chomp.split(",")
    if arr.size > 0
      arr.each do |e|
        strmap=e.split("=")
        if strmap.size > 1
          if re.match(strmap[0])
            result=strmap[1]
          end
        end
      end
    end
    result
  end

  # Takes a comma delimited string of key=val pairs, locates the key, 
  # sets the value and returns the modified string. 
  # returns nil if the string is not comma delimited
  def set_value_cdstr(line,keypattern,value,comma_terminated=true)
    result=""
    match_found=false
    re=Regexp.new(keypattern)
    arr=line.chomp.split(",")
    if arr.size > 0 #comma delimited check
      arr.each do |e|
        kv="" 
        strmap=e.split("=") #key value split
        if strmap.size == 2 #well formed key value
          if re.match(strmap[0])
            kv="#{strmap[0]}=#{value}"
            match_found=true
          else
            kv="#{strmap[0]}=#{strmap[1]}"
          end
        else
          kv=e
        end
        result+=kv+","
      end
      if not comma_terminated
        result=result.chomp(",")
      end
    end
    result+="\n"
    (match_found)? result:nil
  end

  def saveScript(path, name, content)
    scriptName = File.join(path,name)
    File.open(scriptName, "w+") do |sFile|
      sFile.print(content)
      FileUtils.chmod(0750,scriptName)
      logd "Created file: #{scriptName}"
    end  
  end

  def appendScript(path, name, content)
    scriptName=File.join(path,name)
    File.open(scriptName,"a") do |sFile|
      sFile.print(content)
      logd "Appended to file: #{scriptName}"
    end
  end

  def getBatchJobScript_coldrestart (env,rundir)
    walltime=env.run.walltime
    name=env.run.batchname
    procs=""
    if env.run.proc_id and env.run.proc_line.class == OpenStruct
      procs=env.run.proc_line.send(env.run.proc_id)
    else
      procs=env.run.proc_line
    end
    npes=""
    if env.run.proc_id and env.run.procs_to_int
      npes=env.run.procs_to_int.send(env.run.proc_id)
    else 
      npes=env.run.proc_id
    end
    group=env.run.group
    loadModules=env.run.modules
    runid=env.run.rundeck
    batchScript=<<-eos
#!/bin/bash
#PBS -S /bin/bash
#PBS -N #{name}
#PBS -l #{procs}
#PBS -l walltime=#{walltime}
## does not work:PBS -W group_list= use instead:
#SBATCH -A #{group}
#PBS -j eo

# Cold restart script

# environment setup
. /usr/share/modules/init/bash
module purge
module load #{loadModules} 

export MODELERC=#{rundir}/modelErc

source \$MODELERC

ulimit -s unlimited

cd #{rundir}
pwd
exec/runE #{runid} -np #{npes} -cold-restart
eos
    batchScript
  end

  def getBatchJobScript_warmrestart (env,rundir)
    walltime=env.run.walltime
    name=env.run.batchname
    procs=""
    if env.run.proc_id and env.run.proc_line.class == OpenStruct
      procs=env.run.proc_line.send(env.run.proc_id)
    else
      procs=env.run.proc_line
    end
    npes=""
    if env.run.proc_id and env.run.procs_to_int
      npes=env.run.procs_to_int.send(env.run.proc_id)
    else 
      npes=env.run.proc_id
    end
    group=env.run.group
    loadModules=env.run.modules
    execdir=File.join(env.run.savedisk,env.run.rundeck)
    batchScript=<<-eos
#!/bin/bash
#PBS -S /bin/bash
#PBS -N #{name}
#PBS -l #{procs}
#PBS -l walltime=#{walltime}
## does not work:PBS -W group_list= use instead:
#SBATCH -A #{group}
#PBS -j eo

# Warm Restart script

# environment setup
. /usr/share/modules/init/bash
module purge
module load #{loadModules} 

export MODELERC=#{rundir}/modelErc

source \$MODELERC

ulimit -s unlimited

cd #{execdir}
touch I
mv fort.1.nc 25hr_fort.1.nc
cp fort.2.nc fort.1.nc
./E -np #{npes}
eos
    batchScript
  end

  def getMakeRundeckScript(env)

    script=<<-eos
#!/bin/bash

export MODELERC=#{env.build.dir}/../#{env.build.modelerc}

. /usr/share/modules/init/bash
module purge 
eos
    env.build.modules.each {|mod| script << "module load #{mod}\n"} 
    script2=<<-eos

source \$MODELERC

if [ ! -d "$DECKS_REPOSITORY" ] ; then
  mkdir \$DECKS_REPOSITORY
fi 

if [ ! -d "$CMRUNDIR" ] ; then
  mkdir \$CMRUNDIR
fi

if [ ! -d "$SAVEDISK" ] ; then
  mkdir \$SAVEDISK
fi

cd #{env.build.dir}/decks
make -f #{env.build.makefile} rundeck RUN=#{env.build.rundeck} RUNSRC=#{env.build.rundeck}
eos
    script << script2

    script
  end

  def getMakeSetupScript(env)

    overrides=""
    overrides=env.build.make_overrides if env.build.make_overrides

    script=<<-eos
#!/bin/bash

export MODELERC=#{env.build.dir}/../#{env.build.modelerc}

. /usr/share/modules/init/bash
module purge 
eos
    env.build.modules.each {|mod| script << "module load #{mod}\n"} 

    script2=<<-eos

source \$MODELERC

if [ ! -d "$DECKS_REPOSITORY" ] ; then
  mkdir \$DECKS_REPOSITORY
fi 

if [ ! -d "$CMRUNDIR" ] ; then
  mkdir \$CMRUNDIR
fi

if [ ! -d "$SAVEDISK" ] ; then
  mkdir \$SAVEDISK
fi

cd #{env.build.dir}/decks
make -f #{env.build.makefile} setup RUN=#{env.build.rundeck} #{overrides}
eos
    script << script2

    script  
  end

# Generate the modelErc file from env variables
  def getModelercScript(env)

    mpidistr=""
    mpidir=""
    mpi=""
    mp=""
    baselibdir5=""

    mpidistr=env.build.mpidistr if env.build.mpidistr
    mpidir=env.build.mpidir if env.build.mpidir
    mpi=env.build.mpi if env.build.mpi
    mp=env.build.mp if env.build.mp
    baselibdir5=env.build.baselibdir5 if env.build.baselibdir5

    script=<<-eos
#!/bin/bash

# INTEL MODELERC FILE
# directories and general options
# Need to create the following 4 directories
DECKS_REPOSITORY=#{build_decksrepo(env)}
CMRUNDIR=#{build_cmrundir(env)}
EXECDIR=#{build_execdir(env)}
SAVEDISK=#{build_savedisk(env)}

# This is where the model data (ICs, BCs) is stored
GCMSEARCHPATH=#{env.build.gcmsearchpath}

# leave these alone
OUTPUT_TO_FILES=#{env.build.output_to_files}
VERBOSE_OUTPUT=#{env.build.verbose_output}
OVERWRITE=#{env.build.overwrite}

# compiler
COMPILER=#{env.build.compiler}

# netcdf
NETCDFHOME=#{env.build.netcdfhome}
PNETCDFHOME=#{env.build.pnetcdfhome}

# mpi
MPIDISTR=#{mpidistr}
MPIDIR=#{mpidir}
MPI=#{mpi}

# esmf and/or basedir
ESMF=#{env.build.esmf}
BASELIBDIR5=#{baselibdir5}

# other options
MP=#{mp}
eos

  script
  end

  def modifyModelercScript(env)

    script=<<-eos
# These entries override this file for execution in a different path
CMRUNDIR=#{env.run.cmrundir}
SAVEDISK=#{env.run.savedisk}
eos

  script

  end

  def build_cmrundir (env)
    File.join(env.build.dir,"..",env.build.cmrundir)
  end

  def build_decksrepo (env)
    File.join(env.build.dir,"..",env.build.decks_repository)
  end

  def build_execdir (env)
    File.join(env.build.dir,"..",env.build.execdir)
  end

  def build_savedisk (env)
    File.join(env.build.dir,"..",env.build.savedisk)
  end

  def lib_re_str_job_id
    '(\d+).*'
  end

  def lib_submit_script
    'qsub'
  end

  def run_batch_job(env,rundir,scriptname)
    jobid=nil
    re1=Regexp.new(lib_re_str_job_id)
    ss=lib_submit_script
    ss+=" #{scriptname}" 
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
    outfile=File.join(env.run.savedisk,env.run.rundeck,"run_status")
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

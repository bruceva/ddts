require 'net/smtp'
require 'open3'

module Library

  # REQUIRED METHODS (CALLED BY DRIVER)

  # ************************** Common build functions *********************
  def lib_build_prep_common(env)
    # Construct the name of the build directory and store it in the env.build
    # structure for later reference. The value of env.build._root is supplied
    # internally by the test suite; the value of env.run.build is supplied by
    # the run config.
    buildscript="build.sh"
    srcdir=File.join("..","src")
    env.build.dir=File.join(env.build._root,env.run.build)
    sourceexists=File.exists?(File.join(srcdir,buildscript))         
    Thread.exclusive do
       forcebuild=File.join(srcdir,"ddts.forcebuild")
       if not sourceexists 
          logi "First time code checkout"
          cmd="svn co svn+ssh://progressdirect/svn/nu-wrf/code/trunk #{srcdir}"
          ext(cmd,{:msg=>"SVN checkout failed",:out=>true})
          # Copy the source files, recursively, into the build directory.
          FileUtils.touch(forcebuild)
          logi "Created force build bread crumb"
          if Dir.exist?(env.build.dir) 
             logi "Removing previous build directory"
             FileUtils.rm_rf(env.build.dir)
          end
          logi "Copying #{srcdir} -> #{env.build.dir}"
          FileUtils.cp_r(srcdir,env.build.dir,{:remove_destination=>true})
       else
          logi "Source code exists"
          if File.exists?(forcebuild)
             # We are sharing the same source directory so if it got changed by the first
             # build thread then we must refresh our own copy of it
             # Copy the source files, recursively, into the build directory.
             logi "Force build found refreshing source copy"
             if Dir.exist?(env.build.dir) 
                logi "Removing previous build directory"
                FileUtils.rm_rf(env.build.dir)
             end
             logi "Copying #{srcdir} -> #{env.build.dir}"
             FileUtils.cp_r(srcdir,env.build.dir,{:remove_destination=>true})
          else 
             logi "Running source code update"          
             cmd="svn update #{srcdir}"
             o,s=my_ext(cmd,{:msg=>"SVN update failed",:out=>true,:die=>true})
             if o.length > 0 and o.grep(/^Updated|updated/).length > 0 
                logi "Source code updated"              
                FileUtils.touch(forcebuild)
                logi "Created force build bread crumb"
                if Dir.exist?(env.build.dir)
                   logi "Removing previous build directory"
                   FileUtils.rm_rf(env.build.dir)
                end
                # Copy the source files, recursively, into the build directory.
                logi "Copying #{srcdir} -> #{env.build.dir}"
                FileUtils.cp_r(srcdir,env.build.dir,{:remove_destination=>true})
             else
                logi "SVN update revealed no change of repository working copy"
                if not Dir.exist?(env.build.dir)
                  logi "Build directory does not exist"
                  # Copy the source files, recursively, into the build directory.
                  logi "Copying #{srcdir} -> #{env.build.dir}"
                  FileUtils.cp_r(srcdir,env.build.dir)
                end
             end
          end
       end
    end
    env.build.dir
  end

  def lib_build_common(env)
    # Construct the command to execute in a subshell to perform the build.
    buildscript="build.sh"
    mparam = env.build.param
    logd "Make file param: #{mparam}"
    logd "env.build.dir = #{env.build.dir}"
    buildfile=File.join(env.build.dir,buildscript) 
    execfile=File.join(env.build.dir,"WRFV3","run","wrf.exe")
    execexists=File.exists?(execfile)
    forcebuild=File.join(env.build.dir,"ddts.forcebuild")
    if !execexists || File.exists?(forcebuild) 
       
       buildcommand="#{buildfile} "  # start building the command string

       if !env.build.config || env.build.config.nil? == true
         logd "No --config defined. Allowing build to choose" 
         # no change to buildcommand
       else
         logd "Using --config #{env.build.config}" 
         buildcommand="#{buildcommand} --config #{env.build.config} "
       end
       
       if !env.build.debug || env.build.debug.nil? == true
         logd "Debug not specified or false." 
         # no change to buildcommand
       else
         logd "Debug build selected" 
         buildcommand="#{buildcommand} debug "
       end
       
       buildcommand="#{buildcommand} #{mparam}"
       cmd="cd #{env.build.dir} && #{buildcommand}"
       # Execute external command via ext() (defined in ts.rb).
       o,s=ext(cmd,{:msg=>"Build failed, see #{logfile}"})
       if s==0 and File.exists?(forcebuild) #Build completed
         FileUtils.rm(forcebuild) 
         logd "Deleted #{forcebuild} breadcrumb"
       end         
    else
      logd "Skipping build. No change of working copy to repository"
    end
  end

  def lib_build_post_common(env,output)
    # Copying these files effectively checks for their existance. 
    logd "env.build.dir = #{env.build.dir}"
    logd "env.build.bindir = #{env.build.bindir}"
    bindir=File.join(env.build.dir,env.build.bindir)
    FileUtils.mkdir_p(bindir)
    exeslist=env.build.executables
    exeslist.each_with_index do |exe, index|
       FileUtils.cp(File.join(env.build.dir,exe),bindir)
       logd "Copied #{index} #{exe} -> #{bindir}"
    end
    # Return the name of the dir to be copied for each run that requires it.
    env.build.dir
  end

  def lib_data_common(env)
    logd "No data-prep needed for common run."
    # s=env.inspect()
    # logd "#{s}"
  end

  def lib_run_prep_common(env,rundir)
    logd "Rundir: #{rundir}"
    # Link run (executables, support data) files.
    files=Dir[File.join(env.build._result,"WRFV3","run","*")]
    files.each do |x| 
      logd "sym linking run file: #{x}"
      FileUtils.ln_sf(x,rundir) 
    end  

    # Link specific test case input data.
    files=Dir[File.join(env.run.testDataRepository,env.run.testCaseNumber,"regtest","input","*")]
    files.each do |x|
      # lis.config is a special file that is subject to modification for this
      # run and as such must be a copy of the original.
      if x.include?('lis.config')
        logd "copying input data file: #{x}"
        FileUtils.cp(x,rundir)
        modifyLisConfig(env,rundir)
      else
        logd "sym linking input data file: #{x}"
        FileUtils.ln_sf(x,rundir)
      end
    end
 
    # Return rundir (i.e. where to perform the run).
    rundir
  end

  # *********************** WEEKLY build functions **************************
  def lib_run_batch(env,rundir)
    # Create the batch system script with information from the 
    # run conf file.
    s = createBatchJobScript(env,rundir)
    fileName = File.join(rundir,batch_filename(env))
    File.open(fileName, "w+") do |batchFile|
      batchFile.print(s)
      logd "Created batch file: #{fileName}"
    end
    # Submit the script to the batch system
    run_batch_job(env,rundir)

    # The last line of this function must return the file that will be used to gauge
    # execution success.
  end

  def lib_outfiles_batch(env,path)
    logd "lib_outputfiles->path-> #{path}"
    env.run.expectedOutputFiles.map { |x| [path,x] }
    #Note must return list with [path,file] pairs or empty one 
  end

  def lib_queue_del_cmd_batch(env)
    'qdel'
  end

  def re_str_success_batch
    "wrf: SUCCESS COMPLETE WRF"
  end

  # ********************* default functions *********************
  def lib_outfiles(env,path)
    logd "lib_outputfiles->path-> #{path}"
    if env.run.out_file_name
      [[path,env.run.out_file_name]]
    else
      []
    end
  end

  def lib_queue_del_cmd(env)
    'echo'
  end

  def lib_run_post(env,runkit)
    logd "Verifying run success..."
    stdout=runkit
    (job_check(stdout, re_str_success))?(true):(false)
  end

  def lib_suite_prep(env)
    logd "Preping suite"
  end

  def lib_suite_post(env)
    # remove force build breadcrumb file
    forcebuild=File.join("..","src","ddts.forcebuild")
    if File.exists?(forcebuild)
      logi "Deleting force build file: #{forcebuild}"
      FileUtils.rm (forcebuild)
    end
 
    # send mail
    suite_name=env.suite._suitename
    email_from=env.suite.email_from
    email_to=env.suite.email_to
    email_subject=env.suite.email_subject
    email_server=env.suite.email_server
    email_ready=true if email_server and email_from and email_to and email_subject
    if env.suite._totalfailures > 0 
      msg="#{env.suite._totalfailures} TEST(S) OUT OF #{env.suite._totalruns} FAILED" 
      subject="#{email_subject} -- #{suite_name} (FAILED)"
      send_email(email_from,email_to,subject,email_server,msg,true) if email_ready
    else
      msg="ALL TESTS PASSED"
      subject="#{email_subject} -- #{suite_name} (COMPLETED)"
      send_email(email_from,email_to,subject,email_server,msg,false) if email_ready  
    end
    logi env.inspect()
  end

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

  def lib_re_str_job_id
    '(\d+).*'
  end

  def lib_submit_script
    'qsub'
  end

  def batch_filename(env)
    "runWrf_#{env.run.proc_id}.job"
  end

  def run_batch_job(env,rundir)
    jobid=nil
    re1=Regexp.new(lib_re_str_job_id)
    ss=lib_submit_script+" "
    ss+=batch_filename(env) 
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
    File.join(rundir,"rsl.out.0000")
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

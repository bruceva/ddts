require 'net/smtp'

module Library

  # REQUIRED METHODS (CALLED BY DRIVER)

  # ************************** Common build functions *********************
  def lib_build_prep_common(env)
    # Construct the name of the build directory and store it in the env.build
    # structure for later reference. The value of env.build._root is supplied
    # internally by the test suite; the value of env.run.build is supplied by
    # the run config.
    env.build.dir=File.join(env.build._root,env.run.build)
    buildfile=File.join(env.build.dir,"build.sh")
    sourceexists=File.exists?(buildfile)
    cmd="cd .. && svn status src"
    Thread.exclusive do
       o=ext(cmd,{:msg=>"SVN status failed"})
       if o[0].length > 0 || !sourceexists       
          cmd="cd .. && svn co svn+ssh://progressdirect/svn/nu-wrf/code/trunk src"
          ext(cmd,{:msg=>"SVN checkout failed",:out=>true})      
          # Construct the path to the source files. Wrapping in valid_dir() (defined
          # in ts.rb) ensures that it actually already exists.
          srcdir=valid_dir(File.join("..","src"))
          # Copy the source files, recursively, into the build directory.
          FileUtils.cp_r(srcdir,env.build.dir)
          logd "Copied #{srcdir} -> #{env.build.dir}"
       else
          logd "SVN checkout skipped.  No change of working copy to repository"
       end
    end
    env.build.dir
  end

  def lib_build_common(env)
    # Construct the command to execute in a subshell to perform the build.
    mparam = env.build.param
    logd "Make file param: #{mparam}"
    logd "env.build.dir = #{env.build.dir}"
    buildfile=File.join(env.build.dir,"build.sh") 
    execfile=File.join(env.build.dir,"WRFV3","run","wrf.exe")
    buildexists=File.exists?(execfile)
    # check SVN status. Build only when changes have occurred.
    cmd="cd .. && svn status src"
    o=ext(cmd,{:msg=>"SVN status failed"})
    if (o[0].length > 0) || !buildexists 
       if !env.build.config || env.build.config.nil? == true
         logd "No --config defined. Allowing build to choose" 
         cmd="cd #{env.build.dir} && #{buildfile} #{mparam}"
       else
         logd "Using --config #{env.build.config}" 
         cmd="cd #{env.build.dir} && #{buildfile} --config #{env.build.config} #{mparam}"
       end
       # Execute external command via ext() (defined in ts.rb).
       ext(cmd,{:msg=>"Build failed, see #{logfile}"})
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
      logd "sym linking input data file: #{x}"
      FileUtils.ln_sf(x,rundir)
    end
 
    # Return rundir (i.e. where to perform the run).
    rundir
  end

  # *********************** WEEKLY build functions **************************
  def lib_run_batch(env,rundir)
    # Create the batch system script with information from the 
    # run conf file.
    s = createBatchJobScript(env,rundir)
    fileName = File.join(rundir,env.run.testCaseJobFile)
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

  def lib_re_str_success_batch(env)
    "wrf: SUCCESS COMPLETE WRF"
  end

  # *********************** MOCK build functions **************************

  def lib_build_prep_mock (env)
     logd "Preping mock build..."
    # Construct the name of the build directory and store it in the env.build
    # structure for later reference. The value of env.build._root is supplied
    # internally by the test suite; the value of env.run.build is supplied by
    # the run config.
    env.build.dir=File.join(env.build._root,env.run.build)
  end

  def lib_build_mock(env)
    logd "Mock building..."
    logd "env.build.dir = #{env.build.dir}"
    mparam = env.build.param
    cmd=(mparam != "pass")?("fakecommand #{mparam}"):("echo build #{mparam}")
    ext(cmd,{:msg=>"Mock command failed, see #{logfile}"})
  end

  def lib_build_post_mock(env,output)
    # Move the executables into a directory of their own.
    logd "env.build.dir = #{env.build.dir}"
    logd "env.build.bindir = #{env.build.bindir}"
    logd "env.build.executables = #{env.build.executables}"
    bindir=File.join(env.build.dir,env.build.bindir)
    FileUtils.mkdir_p(bindir)
    exeslist=env.build.executables
    exeslist.each_with_index do |exe, index|
       logd "#{index} : #{exe}"
    end 
    # Return the name of the bin dir to be copied for each run that requires it.
    bindir
  end

  def lib_data_mock(env)
    logd "No data-prep needed for mock run."
  end

  def lib_run_prep_mock(env,rundir)
    # Note: The value of env.build.runfiles is provided internally by the test suite.
    # Simulate some job preping activity
    logd "Runfiles: #{env.build.runfiles}"
    logd "Rundir: #{rundir}"
    logd "Copied #{env.build.runfiles} -> #{rundir}"
    # Return rundir (i.e. where to perform the run).
    rundir
  end

  def lib_run_mock(env,rundir)
    # Construct the command to execute in a subshell to perform the run.
    cmd="cd #{rundir} && echo \"Executed mock with success.\" >> stdout"
    # Execute external command via ext() (defined in ts.rb).
    ext(cmd,{:msg=>"Run failed, see #{logfile}"})
    # Return the path to the run's 'stdout' file.
    File.join(rundir,"stdout")
  end

  def lib_re_str_success_mock(env)
    "Executed mock with success."
  end

  # ********************* default functions *********************
  def lib_outfiles(env,path)
    logd "lib_outputfiles->path-> #{path}"
    []
  end

  def lib_queue_del_cmd(env)
    'echo'
  end

  def lib_run_post(env)
    logd "Post run processing..."
  end

  def lib_suite_prep(env)
    logd "Preping suite"
  end

  def lib_suite_post(env)
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
  end

  # *************************************************************
  # CUSTOM METHODS (NOT CALLED BY DRIVER)

  def createBatchJobScript (env,rundir)
    walltime=env.run.wallTime
    name=env.run.batchName
    procs=env.run.procLine
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
mpirun -np 72 ./wrf.exe
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

  def run_batch_job(env,rundir)
    jobid=nil
    re1=Regexp.new(lib_re_str_job_id)
    ss=lib_submit_script
    ss+=" #{env.run.testCaseJobFile}" 
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

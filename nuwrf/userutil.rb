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

  def getSourceRepository (env)
    repo_info=nil
    if env.build.code_repos and env.build.repo_select
      repo_info=env.build.code_repos.send(env.build.repo_select)
    else
      logw "Missing build code_repos and/or repo_select variables"
    end
    # repo_info is an array with two strings. 
    # The first contains the protocol and the second the repo path
    repo=nil
    if repo_info and repo_info.length == 2
      repo="#{repo_info[0]}://#{repo_info[1]}"
    else
      logw "Incomplete code_repos information"
    end
    repo
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

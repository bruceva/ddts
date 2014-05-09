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

  #send only allows single variable dereferencing
  #This function allow multiple level dereferencing 
  #with a dot separated string of variables
  #ex: ref='input.ungrib'
  def deref(run,ref)
    result=run
    ref.split('.').each do |r|
      result=result.send(r) if result
    end
    result 
  end

  def getPreprocessorScriptName(p)
    p+'.bash'
  end

  #Given an opestruct run,create the list of expected input files
  #for the given processor.
  def expectedInput(run,processor)
    #logi "Getting input for #{processor}"
    result=[]
    refs=run.expectedInputFiles.send(processor)
    #logi "Found #{refs}"
    if refs
      if refs.class == String
        result<<deref(run,refs)  
      elsif refs.class == Array
        refs.each do |ref|
          r=deref(run,ref)
          result<<r if r 
        end
      end
    end
    #logi "input results: #{result}"
    result
  end

  def createCommonScript(env)

    header=<<-eos
#!/bin/bash

# --- shared script used by compilation and run scripts ----

source /usr/share/modules/init/sh
module purge
unset LD_LIBRARY_PATH

# Make sure stacksize is unlimited
ulimit -s unlimited

LDTDIR=#{env.build._root}

eos

    vars_section="#Script variables\n\n"
    if env.build.ldt_script_vars
      vars=env.build.ldt_script_vars.send(env.build.ldt_script_vars_select)
      vars.each do |var|
        vars_section<<"#{var[0]}=\"#{var[1]}\"\n"
      end
      vars_section<<"\n"
      #logi vars_section
    end

    mod_section="#Module\n\n"
    if env.build.ldt_modules
      mods=env.build.ldt_modules.send(env.build.ldt_modules_select)
      mod_section<<"module load #{mods}\n\n"
      #logi mod_section
    end

    exports_section="#Exports\n\n"
    if env.build.ldt_exports
      exports=env.build.ldt_exports.send(env.build.ldt_exports_select)
      exports.each do |exp|
        exports_section<<"export #{exp[0]}=#{exp[1]}\n"
        if exp[2] == 'add_check' 
          exports_section<<"ls -d \$#{exp[0]} || exit 1\n\n"   
        end
      end
      exports_section<<"\n"
      #logi exports_section
    end

    header+vars_section+mod_section+exports_section
  end

  def createConfigureScript(env,commonscript,scriptout)

    default=<<-eos
#!/bin/bash

#load environment
source #{commonscript}

#creation of make/configure.ldt
./configure  > #{scriptout}
eos
 
  default
  end

  def createConfigureResponseScript(env, configurescript)

    header=<<-eos
#!/usr/bin/expect

# must answer question within 5 seconds
set timeout 2

spawn ./#{configurescript}

eos
    body="#Expected question and answers:\n"
    if env.build.configure_qa_list and env.build.configure_qa
      env.build.configure_qa_list.each do |qa|
        q,a=env.build.configure_qa.send(qa)
        body<<"expect \"#{q}\"\n"
        body<<"send -- \"#{a}\"\n" 
      end
      body<<"expect eof\n"
    end

    header+body

  end

  def createBuildScript(env,commonscript,scriptout)

    default=<<-eos
#!/bin/bash

#load environment
source #{commonscript}

# Default configuration requires 10 enter inputs!
./compile > #{scriptout}
eos

  default
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

  def createLDTScript(env,commonscript,scriptout)

    header=createPreprocessorHeader(env,'ldt')

    body=<<-eos
#!/bin/bash

#load environment
source #{commonscript}

ln -fs $LDTDIR/LDT LDT || exit 1
if [ ! -e LDT ] ; then 
    echo "ERROR, LDT does not exist!"
    exit 1
fi

# Execute
./LDT #{env.run.ldt_config} > #{scriptout}
eos

  header+body

  end

  def lib_re_str_job_id
    '(\d+).*'
  end

  def lib_submit_script
    'sbatch'
  end

  def batch_filename(env)
    "runWrf_#{env.run.proc_id}.job"
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
      logd "ERROR: #{outfile} not found"
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
      to_array= to.split(",")
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

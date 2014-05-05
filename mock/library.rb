require 'net/smtp'
require 'open3'

module Library

  # REQUIRED METHODS (CALLED BY DRIVER)

  # *********************** MOCK build functions **************************

  def lib_build_prep_mock (env)
     logd "Preping mock build..."
    # Construct the name of the build directory and store it in the env.build
    # structure for later reference. The value of env.build._root is supplied
    # internally by the test suite; the value of env.run.build is supplied by
    # the run config.
    env.build.dir=env.build._root
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
    if env.run.out_file_name && env.run.out_file_content
      cmd="cd #{rundir} && echo \"#{env.run.out_file_content}\" >> #{env.run.out_file_name}"
      ext(cmd,{:msg=>"Run failed, see #{logfile}"})
    end
    # Construct the command to execute in a subshell to perform the run.
    cmd="cd #{rundir} && echo \"Executed mock with success.\" >> stdout"
    # Execute external command via ext() (defined in ts.rb).
    ext(cmd,{:msg=>"Run failed, see #{logfile}"})
    # Return the path to the run's 'stdout' file.
    File.join(rundir,"stdout")
  end

  def re_str_success_mock
    "Executed mock with success."
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

require 'userutil'

module Library

  include UserUtil

  # REQUIRED METHODS (CALLED BY DRIVER)
  def lib_suite_prep(env)
    # note: env contains only .suite members
  end

  def lib_build_prep(env)
    Thread.exclusive do
      # Construct the name of the build directory and store it in the env.build
      # structure for later reference. The value of env.build.root is supplied
      # internally by the test suite; the value of env.run.build is supplied by
      # the run config.
      env.build.dir=env.build._root
      # Construct the path to the source files. Wrapping in valid_dir() (defined
      # in ts.rb) ensures that it actually already exists.
      srcdir=valid_dir(File.join("..","src"))
      # clone the Smvgear repository
      cmd="cd #{srcdir} && git pull git://github.com/megandamon/SMVgear.git master"
      ext(cmd,{:msg=>"Pull failed, see #{logfile}"})
      # Copy the source files, recursively, into the build directory.
      FileUtils.cp_r(srcdir,env.build.dir)
      logd "Copied #{srcdir} -> #{env.build.dir}"
    end
  end

  def lib_build(env)

    script=<<-eos
#!/bin/bash
. /usr/share/modules/init/bash 
eos
    env.build.modules.each {|mod| script << "module load #{mod}\n"} 

    script2=<<-eos
cd #{env.build.dir}
make -f #{env.build.makefile}
eos
    script << script2
    logi script
    scriptName = File.join(env.build.dir,"makescript.bash")
    File.open(scriptName, "w+") do |sFile|
      sFile.print(script)
      FileUtils.chmod(0700,scriptName)
      logd "Created batch file: #{scriptName}"
    end

    #cmd="source /usr/share/modules/init/bash && module load comp/intel-13.1.3.192 && cd #{env.build.dir} && make"
    cmd="#{scriptName}"
    ext(cmd,{:msg=>"Build failed, see #{logfile}"})
  end

  def lib_build_post(env,output)
    # Move the executables into a directory of their own.
    bindir=File.join(env.build.dir,"bin")
    FileUtils.mkdir_p(bindir)
    [
      "Do_Smv2_Solver.exe"
    ].each do |x|
      FileUtils.mv(File.join(env.build.dir,x),bindir)
      logd "Moved #{x} -> #{bindir}"
    end
    # Return the name of the bin dir to be copied for each run that requires it.
    bindir
  end

  def lib_data(env)
    logd "No data-prep needed."
  end

  def lib_run_prep(env,rundir)
    # Copy executable dir into run directory. The value of env.build._result
    # is provided internally by the test suite.
    logi env.build._result
    FileUtils.cp_r(env.build._result,rundir)
    logd "Copied #{env.build._result} -> #{rundir}"
    # Since the executables are in a subdirectory of the run directory, update
    # rundir to reflect this.
    rundir=File.join(rundir,File.basename(env.build._result))
    # Link data.
    datadir=valid_dir(File.join("..","src"))
    [
      "physproc_entry.proc0017",
      "smv2chem1_entry.proc0017",
      "smv2chem2_entry.proc0017"
    ].each { |x| FileUtils.ln_sf(File.join(datadir,x),rundir) }
    # Return rundir (i.e. where to perform the run).
    rundir
  end

  def lib_run(env,rundir)
      # Construct the command to execute in a subshell to perform the run.
      cmd="cd #{rundir} && ./Do_Smv2_Solver.exe > stdout"
      # Execute external command via ext() (defined in ts.rb).
      ext(cmd,{:msg=>"Run failed, see #{logfile}"})
      # Return the path to the run's 'stdout' file.
      File.join(rundir,"stdout")
  end

  def lib_run_post(env,runkit)
    logd "Verifying run success..."
    stdout=runkit
    (job_check(stdout, re_str_success))?(true):(false)
  end

  def lib_outfiles(env,path)
    [
      [path,"physproc_exit.proc0017"],
      [path,"smv2chem1_exit.proc0017"],
      [path,"smv2chem2_exit.proc0017"]
    ]
  end

  def lib_queue_del_cmd(env)
    nil
  end

  def re_str_success
    "Exiting doSmv2Solver"
  end

  def lib_suite_post(env)

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
  end

  # CUSTOM METHODS (NOT CALLED BY DRIVER)

end

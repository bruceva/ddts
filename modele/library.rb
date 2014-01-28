require 'userutil'

module Library

  include UserUtil

  # REQUIRED METHODS (CALLED BY DRIVER)
  def lib_suite_prep(env)
    # note: env contains only .suite members
    env.suite.cleanupfiles=Array.new
  end

  def lib_build_prep(env)
    Thread.exclusive do
      # Construct the path to the source files. 
      srcdir=File.join("..",env.build.git_repo_branch)
      forcebuild=File.join(srcdir,"ddts.forcebuild")
      if not env.suite.cleanupfiles
        logi "cleanupfiles not found in suite"
        #env.suite.cleanupfiles=Array.new
        #env.suite.cleanupfiles<<forcebuild
      else
        logi "clenaupfiles found in suite"
        env.suite.cleanupfiles<<forcebuild
      end
      env.build.foobar=true
      # Construct the name of the build directory and store it in the env.build
      # structure for later reference. The value of env.build.root is supplied
      # internally by the test suite; the value of env.run.build is supplied by
      # the run config.
      env.build.dir=env.build._root
      if Dir.exist?(env.build._root)
        logd "Build dir already exists."
      else
        logd "Build dir does not exist.  Creating it..."
        FileUtils.mkdir_p(env.build._root)
      end
      env.build.dir=File.join(env.build._root,env.build.git_repo_branch)
      if not File.exist?(srcdir)
        cmd="cd .. && git clone #{env.build.git_repo_root}/#{env.build.git_repo_branch} #{env.build.git_repo_branch}"
        my_ext(cmd,{:msg=>"Repository cloning failed, see #{logfile}"})
        logd "Created #{env.build.git_repo_branch} clone for the first time"
        FileUtils.touch(forcebuild)
        logi "Created force build bread crumb"          
      else
        logi "Source code #{srcdir} exists"
        cmd="cd #{srcdir} && git pull"
        o,s=my_ext(cmd,{:msg=>"Repository update failed, see #{logfile}"})
        if o.length > 0 and o.grep(/^Already up-to-date/).length > 0
          logi "Source code already up-to-date"
        else
          logi "Source code updated"
          FileUtils.touch (forcebuild)
          logi "Created force build bread crumb"
        end        
      end
      if File.exists?(forcebuild) or not Dir.exist?(env.build.dir)
        if Dir.exist?(env.build._root)
          logi "Removing previous #{env.build._root} build directory"
          FileUtils.rm_rf(env.build._root)
          FileUtils.mkdir_p(env.build._root)
        end
        # Copy the source files, recursively, into the build directory.
        logi "Copying #{srcdir} -> #{env.build.dir}"
        FileUtils.cp_r(srcdir,env.build.dir,{:remove_destination=>true})       
      end
    end
  end

  def lib_build(env)
    savediskdir=build_savedisk(env)
    execfile=File.join(savediskdir,env.build.rundeck,env.build.rundeck+".exe")
    logd "Will check if executable #{execfile} exists"
    forcebuild=File.join(env.build.dir,"ddts.forcebuild")

    if not File.exists?(execfile) or File.exists?(forcebuild)
      scriptDir=File.join(env.build.dir,"..")
      saveScript(scriptDir,env.build.modelerc,getModelercScript(env))
      saveScript(scriptDir,"makerundeck.bash",getMakeRundeckScript(env))
      saveScript(scriptDir,"makesetup.bash",getMakeSetupScript(env))
    
      cmd=File.join(scriptDir,"makerundeck.bash")
      ext(cmd,{:msg=>"Build rundeck failed, see #{logfile}"})

      cmd=File.join(scriptDir,"makesetup.bash")
      o,s=ext(cmd,{:msg=>"Build setup failed, see #{logfile}"})
      
      if File.exists?(execfile)
        logd "#{execfile} exists"
        if File.size?(execfile) == 0
          die("Error: #{execfile} has 0 size") 
        end
      else
        die("Error: #{execfile} not found")
      end

      #Build completed
      if File.exists?(forcebuild)
        FileUtils.rm(forcebuild)
        logd "Deleted #{forcebuild} breadcrumb"
      end

    else
      logd "Skipping build. Required executable exists and repository did not change"
    end

  end

  def lib_build_post(env,output)
    # Move the executables into a directory of their own.
    savediskdir=build_savedisk(env)
    modelerc=File.join(env.build.dir,"..",env.build.modelerc)
    # Return the name of the bin dir to be copied for each run that requires it.
    [savediskdir,modelerc,env.build.rundeck,env.build.cmrundir,env.build.dir]
  end

  def lib_data(env)
    #logd "No data-prep needed."
  end

  def lib_run_prep(env,rundir)
    # Copy executable dir into run directory. The value of env.build._result
    # is provided internally by the test suite.
    logi env.build._result
    outdir=env.build._result[0]
    FileUtils.cp_r(outdir,rundir)
    logd "Copied #{outdir} -> #{rundir}"

    modelerc=env.build._result[1]
    FileUtils.cp_r(modelerc,rundir)
    logd "Copied #{modelerc} -> #{rundir}"

    env.run.modelerc=modelerc
    env.run.savedisk=File.join(rundir,File.basename(outdir))
    env.run.rundeck=env.build._result[2]
    env.run.cmrundir=File.join(rundir,env.build._result[3])
    env.run.modelEexec=File.join(env.build._result[4],'exec')

    #Create cmrundir with corresponding symlink to the output rundeck  
    FileUtils.mkdir(env.run.cmrundir)
    FileUtils.ln_s(File.join(env.run.savedisk,env.run.rundeck),File.join(env.run.cmrundir,env.run.rundeck))

    #Create a symlink to the source exec directory containing the script used during the run process.
    FileUtils.ln_s(env.run.modelEexec, rundir)
    # Touch the I file to be able to run again
    #FileUtils.touch(File.join(env.run.savedisk,env.run.rundeck,"I"))

    #Modify the modelErc file used during compilation to run under new directory
    appendScript(rundir,File.basename(env.run.modelerc),modifyModelercScript(env)) 
   
    # Since the executables are in a subdirectory of the run directory, update
    # rundir to reflect this.
    #rundir=File.join(rundir,File.basename(env.build._result))
    # Link data.
    #datadir=valid_dir(File.join("..","src"))
    #[
    #  "physproc_entry.proc0017",
    #  "smv2chem1_entry.proc0017",
    #  "smv2chem2_entry.proc0017"
    #].each { |x| FileUtils.ln_sf(File.join(datadir,x),rundir) }
    # Return rundir (i.e. where to perform the run).
    rundir
  end

  def lib_run(env,rundir)
    logi "Env.build.foobar: #{env.build.foobar}"
    # Create the batch system script with information from the 
    # run conf file.
    s = getBatchJobScript(env,rundir)
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


  def lib_run_post(env,runkit)
    logd "Verifying run success..."
    stdout=runkit
    result=job_check(stdout, re_str_success)
    logd "Result of searching #{stdout} for pattern #{re_str_success}: #{result}"
    result
  end

  def lib_outfiles(env,path)
    outpath=File.join(env.run.savedisk,env.run.rundeck)
    logd "outpath: #{outpath}"
    [
      [outpath,"fort.2.nc"]
    ]
  end

  def lib_queue_del_cmd(env)
    nil
  end

  def re_str_success
    "^Terminated normally.*"
  end

  def lib_suite_post(env)
    # remove force build breadcrumb file
    logi "Suite post processing"
    logi env.inspect()
    if env.suite.cleanupfiles
      logi "Possible files to cleanup"
      env.suite.cleanupfiles.each do |x|
        logi "Checking temp file #{x}" 
        if File.exists?(x)
          logi "Deleting file: #{x}"
          FileUtils.rm (x)
        else
          logi "File #{x} does not exist."
        end
      end
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
  end

  # CUSTOM METHODS (NOT CALLED BY DRIVER)

end

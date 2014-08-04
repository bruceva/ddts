require 'userutil'

module Library

  include UserUtil

  # REQUIRED METHODS (CALLED BY DRIVER)

  # ************************** Common build functions *********************

  def lib_build_prep(env)
    # Construct the name of the build directory and store it in the env.build
    # structure for later reference. The value of env.build.ddts_root is supplied
    # internally by the test suite; the value of env.run.build is supplied by
    # the run config.
    buildscript="build.sh"
    srcdir=File.join("..","src")
    env.build.dir=env.build.ddts_root
    sourceexists=File.exists?(File.join(srcdir,buildscript))
    Thread.exclusive do
       forcebuild=File.join(srcdir,"ddts.forcebuild")
       if not sourceexists
          logi "First time code checkout"
          repo=getSourceRepository(env)
          cmd="svn co #{repo} #{srcdir}"
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
                if not File.exist?(File.join(env.build.dir,buildscript))
                  logi "Build.sh file does not exist"

                  if Dir.exist?(env.build.dir)
                    logd "Removing build directory to avoid copy misplacement"
                    FileUtils.rm_rf(env.build.dir)
                  end

                  # Copy the source files, recursively, into the build directory.
                  logi "Copying #{srcdir} -> #{env.build.dir}"
                  FileUtils.cp_r(srcdir,env.build.dir,{:remove_destination=>true})
                end
             end
          end
       end

       #Sanity check revision information of local repo copy and build copy
       #It is possible that the local source repo is current but a local
       #build missed an update.
       logd "Retrieving local source repository info"
       cmd="svn info #{srcdir}"
       o,s=my_ext(cmd,{:msg=>"SVN info failed",:out=>true,:die=>false})
       env.build.local_src_rev="????"
       if o.length > 0 and o.grep(/^Revision/).length > 0
         env.build.local_src_rev= o.grep(/^Revision/)[0].split(":")[1].strip
       end
       logd "Revision: #{env.build.local_src_rev}"


       logd "Retrieving build target repository info"
       cmd="svn info #{env.build.dir}"
       o,s=my_ext(cmd,{:msg=>"SVN info failed",:out=>true,:die=>false})
       env.build.build_src_rev="????"
       if o.length > 0 and o.grep(/^Revision/).length > 0
         env.build.build_src_rev= o.grep(/^Revision/)[0].split(":")[1].strip
       end
       logd "Revision: #{env.build.build_src_rev}"

       if env.build.local_src_rev == "????" or env.build.build_src_rev == "????"
         die ("Unable to verify repo revision!")
       end

       if env.build.local_src_rev != env.build.build_src_rev
         logi "Build source repo and local copies are not in sync!!!"
         logi "Invalidating build copy"
         if Dir.exist?(env.build.dir)
           logd "Removing build directory to avoid copy misplacement"
           FileUtils.rm_rf(env.build.dir)
         end

         # Copy the source files, recursively, into the build directory.
         logi "Copying #{srcdir} -> #{env.build.dir}"
         FileUtils.cp_r(srcdir,env.build.dir,{:remove_destination=>true})
         logi "Build source repo and local one are now in sync"
         env.build.build_src_rev = env.build.local_src_rev
       end

    end
  end

  def lib_build_prep_old(env)
    # Construct the name of the build directory and store it in the env.build
    # structure for later reference. The value of env.build.ddts_root is supplied
    # internally by the test suite; the value of env.run.build is supplied by
    # the run config.
    buildscript="build.sh"
    srcdir=File.join("..","src")
    env.build.dir=env.build.ddts_root
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

  def lib_build(env,prepkit)
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

  def lib_build_post(env,postkit)
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

  def lib_data(env)
    logd "No data-prep needed for common run."
    # s=env.inspect()
    # logd "#{s}"
  end

  def lib_run_prep(env)
    rundir=env.run.ddts_root
    logd "Rundir: #{rundir}"
    # Link run (executables, support data) files.
    files=Dir[File.join(env.build.ddts_result,"WRFV3","run","*")]
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
  def lib_run(env,prepkit)
    rundir=env.run.ddts_root
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

  def lib_outfiles(env,path)
    logd "lib_outputfiles->path-> #{path}"
    env.run.expectedOutputFiles.map { |x| [path,x] }
    #Note must return list with [path,file] pairs or empty one 
  end

  def lib_queue_del_cmd(env)
    'qdel'
  end

  def re_str_success
    "wrf: SUCCESS COMPLETE WRF"
  end

  # ********************* default functions *********************
  def lib_outfiles_default(env,path)
    logd "lib_outputfiles->path-> #{path}"
    if env.run.out_file_name
      [[path,env.run.out_file_name]]
    else
      []
    end
  end

  def lib_queue_del_cmd_echo(env)
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
    suite_name=env.suite.ddts_suitename
    email_from=env.suite.email_from
    email_to=env.suite.email_to
    email_subject=env.suite.email_subject
    email_server=env.suite.email_server
    email_ready=true if email_server and email_from and email_to and email_subject
    if env.suite.ddts_totalfailures > 0 
      msg="#{env.suite.ddts_totalfailures} TEST(S) OUT OF #{env.suite.ddts_totalruns} FAILED" 
      subject="#{email_subject} -- #{suite_name} (FAILED)"
      send_email(email_from,email_to,subject,email_server,msg,true) if email_ready
    else
      msg="ALL TESTS PASSED"
      subject="#{email_subject} -- #{suite_name} (COMPLETED)"
      send_email(email_from,email_to,subject,email_server,msg,false) if email_ready  
    end
    logi env.inspect()
  end

end

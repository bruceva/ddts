require 'userutil'

module Library

  include UserUtil

  # REQUIRED METHODS (CALLED BY DRIVER)

  def lib_build_prep(env)
    # Construct the name of the build directory and store it in the env.build
    # structure for later reference. The value of env.build._root is supplied
    # internally by the test suite; the value of env.run.build is supplied by
    # the run config.
    buildscript="build.sh"
    srcdir=File.join("..","src")
    env.build.dir=env.build._root
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
    end
    env.build.dir
  end

  def lib_build(env)
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

  def lib_build_post(env,output)
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
    logd "No data-prep needed."
  end

  def lib_run_prep(env,rundir)
    logd "Rundir: #{rundir}"

    # Create the batch system scripts with information from the run conf file.
    s = createCommonPreprocessorScript(env,rundir)
    fileName = File.join(rundir,'common.bash')
    File.open(fileName, "w+") do |batchFile|
      batchFile.print(s)
      logd "Created batch file: #{fileName}"
    end

    env.run.preprocessors.each do |prep|
      s=""
      f=nil
      if prep == 'geogrid'
        s=createGeogridPreprocessorScript(env)
        f='geogrid.bash'
      elsif prep == 'ungrib'
        s=createUngribPreprocessorScript(env)
        f='ungrib.bash'
      elsif prep == 'metgrid'
        s=createMetgridPreprocessorScript(env)
        f='metgrid.bash'
      elsif prep == 'real'
        s=createRealPreprocessorScript(env)
        f='real.bash'
      elsif prep == 'wrf'
        s=createWrfPreprocessorScript(env)
        f='wrf.bash'
      elsif prep == 'rip'
        s=createRipPreprocessorScript(env)
        f='rip.bash'
      end
      if f
        fileName = File.join(rundir,f)
        File.open(fileName, "w+") do |batchFile|
          batchFile.print(s)
          logd "Created batch file: #{fileName}"
        end
      end
    end

    if env.run.namelist_link 
      env.run.namelist_link.each do |link|
        if link.size == 2
          logd "sym linking namelist file: #{link[0]} -> #{link[1]}"
          FileUtils.ln_sf(link[0],File.join(rundir,link[1]))
        end
      end
    end

    if env.run.grib_input 
      files=Dir[File.join(env.run.grib_input,getUngribInputPattern(env))]
      files.each do |x|
        logd "sym linking ungrib input file: #{x}"
        FileUtils.ln_sf(x,rundir) 
      end
    end

    # Return rundir (i.e. where to perform the run).
    rundir
  end

  def lib_run(env,rundir)
    
    env.run.preprocessors.each do |prep|
      # Submit the script to the batch system
      logi "About to submit #{prep} preprocessor job"
      output=run_batch_job(env,rundir,prep)
      logi "Verifying preprocessor result..."
      match=re_str_success(env,prep)
      result=job_check(output, match)
      die ("Preprocessor #{prep} failed, unable to find #{match} in #{result}") if not result
      logi "Pass"
    end

    #Information passed to the run post processing
    rundir
  end

  def lib_outfiles(env,path)
    #Note must return list with [path,file] pairs or empty one 
    logd "lib_outputfiles->path-> #{path}"
    arr=Array.new
    env.run.preprocessors.each do |prep|
      arr+=env.run.expectedOutputFiles.send(prep).map { |x| [path,x] }
    end
    arr
  end

  def lib_queue_del_cmd(env)
    'qdel'
  end

  def re_str_success (env,processor)
    if env.run.expectedStatusFiles
      env.run.expectedStatusFiles.send(processor)[1]
    else
      nil
    end
  end

  def lib_run_post(env,runkit)
    #By the time we get here the run is already deemed a success.
    #Assemble the data structure of information that may be needed by other runs
    #that depend on this.
    {:result=>true,:preprocessors=>env.run.preprocessors,:rundir=>runkit}
  end

  def lib_run_check(env,postkit)
    postkit[:result]
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

end

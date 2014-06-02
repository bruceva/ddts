require 'userutil'

module Library

  include UserUtil

  # REQUIRED METHODS (CALLED BY DRIVER)

  def lib_build_prep(env)
    # Construct the name of the build directory and store it in the env.build
    # structure for later reference. The value of env.build._root is supplied
    # internally by the test suite; the value of env.run.build is supplied by
    # the run config.
    buildscript="compile"
    srcdir=File.join("..","src")
    env.build.dir=env.build._root
    sourceexists=File.exists?(File.join(srcdir,buildscript))         
    Thread.exclusive do
       forcebuild=File.join(srcdir,"ddts.forcebuild")
       if not sourceexists 
          logi "First time code checkout"
          cmd="svn checkout https://progress.nccs.nasa.gov/svn/lis/tools/ldt/7/development #{srcdir}"
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
                  logi "#{buildscript} file does not exist"

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

  def lib_build(env)
    mparam = env.build.param
    logd "Make file param: #{mparam}"
    logd "env.build.dir = #{env.build.dir}"

    commonscript="ddts_common.bash"
    env.build.env_script=commonscript

    # Construct the command to execute in a subshell to perform the build. 
    configure="configure"
    configureout="configure.ldt"
    configurescript="ddts_configure.bash"
    configureresponsescript="ddts_configure.exp"
    configurefile=File.join(env.build.dir,configure)
    configureoutfile=File.join(env.build.dir,'make',configureout)

    build="compile"
    buildscript="ddts_build.bash"
    buildfile=File.join(env.build.dir,build)
    execfile=File.join(env.build.dir,"LDT")
    execexists=File.exists?(execfile)

    forcebuild=File.join(env.build.dir,"ddts.forcebuild")

    # Create the script with information from the build configuration.
    fileName = File.join(env.build.dir,commonscript)
    if not File.exist?(fileName)
      File.open(fileName, "w+") do |sFile|
        s = createCommonScript(env)
        sFile.print(s)
        logd "Created common script file: #{fileName}"
        sFile.chmod(0754)
      end
    else
      logd "Found #{commonscript}"
    end

    if not File.exist?(configureoutfile) or File.exist?(forcebuild)

      # Create the configure script with information from the build configuration.
      fileName = File.join(env.build.dir,configurescript)
      logi fileName
      if not File.exist?(fileName)
        File.open(fileName, "w+") do |sFile|
          s = createConfigureScript(env,commonscript,configurescript+".out")
          sFile.print(s)
          logd "Created configure script file: #{fileName}"
          sFile.chmod(0754)
        end
      end

      # Create the configure response script with information from the build configuration.
      fileName = File.join(env.build.dir,configureresponsescript)
      logi fileName
      if not File.exist?(fileName)
        File.open(fileName, "w+") do |sFile|
          s = createConfigureResponseScript(env,configurescript)
          sFile.print(s)
          logd "Created configure response script file: #{fileName}"
          sFile.chmod(0754)
        end
      end

      cmd="cd #{env.build.dir} && ./#{configureresponsescript}" 
      # Execute external command via ext() (defined in ts.rb).
      o,s=ext(cmd,{:msg=>"Configure failed, see #{logfile}"})
      if s==0 and job_check(File.join(env.build.dir,configurescript+".out"),"file generated successfully")       
        logd "#{configureresponsescript} executed succesfully"
      else
        die ("Error running #{configureresponsescript}")
      end         

    else
      logd "Found #{configureoutfile}"
    end

    if !execexists or File.exist?(forcebuild) 
      
      # Create the build script with information from the build configuration.
      fileName = File.join(env.build.dir,buildscript)
      logi fileName
      if not File.exist?(fileName)
        File.open(fileName, "w+") do |sFile|
          s = createBuildScript(env,commonscript,buildscript+".out")
          sFile.print(s)
          logd "Created build script file: #{fileName}"
          sFile.chmod(0754)
        end
      end
 
      buildcommand="#{buildscript} "  # start building the command string

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
       
      #buildcommand="#{buildcommand} #{mparam}"
      cmd="cd #{env.build.dir} && ./#{buildcommand}"
      # Execute external command via ext() (defined in ts.rb).
      o,s=ext(cmd,{:msg=>"Build failed, see #{logfile}"})
      if s==0 and job_check(File.join(env.build.dir,buildscript+".out"),"Compile finished") 
        logd "Compilation successfull"
        if File.exists?(forcebuild) #Build completed
          FileUtils.rm(forcebuild) 
          logd "Deleted #{forcebuild} breadcrumb"
        end
      else
        die ("Error running #{buildcommand}")
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
    #die("FAKE BUILD ERROR") if env.build.config=='discover.cfg'
    # Return the information structure to be copied for each run that requires it.
    {:dir=>env.build.dir,:env_script=>env.build.env_script,:name=>File.basename(env.build.dir),
     :src_rev=>env.build.local_src_rev,:build_rev=>env.build.build_src_rev}
  end

  def lib_data(env)
    logd "No data-prep needed."
  end

  def lib_run_prep(env,rundir)
    logi "Rundir: #{rundir}"

    #copy the shared environment script from the build directory
    FileUtils.cp(File.join(env.build._result[:dir],env.build._result[:env_script]),rundir)

    env.run.preprocessors.each do |prep|
      s=""
      f=nil
      if prep == 'ldt'
        f='ldt.bash'
        s=createLDTScript(env,env.build._result[:env_script],f+".out")
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
        if link.size == 2 and File.exist?(link[0])
          logd "sym linking namelist file: #{link[0]} -> #{link[1]}"
          FileUtils.ln_sf(link[0],File.join(rundir,link[1]))
        else
          die("Required namelist link not found")
        end
      end
    end

    # Return rundir (i.e. where to perform the run).
    rundir
  end

  def lib_run(env,rundir)
    baselinedir=env.run.baselinedir if env.run.baselinedir
    abortprocessing=false
    run_success=true
    message=""
    laststep=""

    env.run.preprocessors.each do |prep|
      if not run_success
        break;
      end 
   
      laststep=prep

      if 'ldt'.include?(prep)
        arr=expectedInput(env.run,prep)
        if arr and arr.size >  0
          arr.each do |a|
            #logi "#{a.class} #{prep}"
            # Some preprocessors contain files and entire directories as input
            # Files are listed in an array format while directories are single strings
            if a.class == String and 'ungrib gocart2wrf'.include?(prep)
              if Dir.exist?(a)
                logi "Found #{prep} #{a} input directory"
                linkdir=getInputLinkDir(env,prep)
                if linkdir == '.'
                  linkdir=rundir
                else 
                  linkdir=File.join(rundir,linkdir)
                  if not Dir.exist?(linkdir)
                    logi "#{prep} processing: Creating #{linkdir} input directory" 
                    FileUtils.mkdir_p(linkdir)
                  else
                    die ("#{prep} processing: Unable to create link directory #{linkdir}") 
                  end
                end
                files=Dir[File.join(a,getInputPattern(env,prep))]
                files.each do |f|
                  logd "sym linking #{prep} input file: #{f}"
                  FileUtils.ln_sf(f,linkdir)
                end
              else
                message="#{prep} input directory #{a} not found"
                logi "#{message}"
                abortprocessing=true
              end              
            end
            if a.class == Array
              a.each do |f|
                if File.exist?(File.join(rundir,f))
                  logi "#{prep} processing: required input file #{f} exists"
                elsif Dir.exist?(baselinedir) and File.exist?(File.join(baselinedir,f))
                  linkdir=rundir
                  #it is possible that the filename contain a directory structure
                  #if so it must be recreated
                  if File.dirname(f) != "."
                    linkdir=File.join(rundir,File.dirname(f))
                    FileUtils.mkdir_p(linkdir)
                  end
                  #Copy those required inputs that are known to change during processor execution
                  # or risk tainting the source. To save space the read only ones are linked.
                  if f.include?('wrfbdy') or f.include?('wrfinput') or f.include?('namelist.output')
                    logi "#{prep} processing: required input file #{f} not found, copying from baseline in #{baselinedir}"
                    FileUtils.cp(File.join(baselinedir,f),linkdir)
                    #Create special link to the specific file (.real,.casa2wrf,.gocart2wrf,.convert_emiss)
                    lnk=f
                    if f.include?('.real')
                      lnk=f.split('.real')[0]
                    elsif f.include?('.casa2wrf')
                      lnk=f.split('.casa2wrf')[0]
                    elsif f.include?('.gocart2wrf')
                      lnk=f.split('.gocart2wrf')[0]
                    elsif f.include?('.convert_emiss')
                      lnk=f.split('.convert_emiss')[0]
                    end
                    #Create link only if one is not already present.
                    if lnk != f and not File.exist?(File.join(linkdir,lnk))
                      logi "#{prep} processing: linking #{lnk} to #{f}"
                      FileUtils.ln_sf(File.join(linkdir,f),File.join(linkdir,lnk))
                    end
                  else
                    logi "#{prep} processing: required input file #{f} not found, linking to baseline in #{baselinedir}"
                    FileUtils.ln_sf(File.join(baselinedir,f),linkdir)
                  end
                else
                  message= "#{prep} processing: missing required input #{f}"
                  logi "#{message}"
                  abortprocessing=true
                end
              end
            end
          end
        end
      end 

      if abortprocessing
        logd "ERROR: #{prep} processing aborted due to missing data"
        run_success=false
      else
        # Submit the script to the batch system
        logi "About to submit #{prep} preprocessor job"

        #die ("test abort")
        output=run_batch_job(env,rundir,prep)
        logi "Verifying preprocessor result..."
        match=re_str_success(env,prep)
        if File.exist?(output)
          message="Preprocessor #{prep} success"          
          run_success=job_check(output, match)
          message="Preprocessor #{prep} failed, unable to find \"#{match}\" in #{output}" if not run_success
        else
          message="Preprocessor #{prep} failed, unable to locate #{output}"
          run_success=false
        end
        logi "#{message}"
      end
    end

    #Information passed to the run post processing
    {:result=>run_success,:rundir=>rundir,:pipeline=>env.run.preprocessors,:message=>message,:laststep=>laststep,:build=>env.build._result}
  end

  def lib_comp(env,file1, file2, exec_id="")
    logi exec_id
    logi env.inspect()
    die ("comp test")
    #define exec_name=env.?.send(exec_id)
    #define exec_params=env.?.send(exec_id)
    cmd="which #{exec_name}"
    o,s=ext(cmd,{:die=>false,:msg=>"Unable to locate #{exec_name}",:out=>true})
    if o
      logd "Located #{exec_name} at #{o}"
    else
      die ("Unable to located #{exec_name}. Please add it to the PATH env var, or establish alias.")
    end
    if exec_params
      logd "#{exec_name} #{exec_params} comparison of #{file1} against #{file2}"
      cmd="#{exec_name} #{exec_params} #{file1} #{file2}"
    else
      logd "#{exec_name} comparison of #{file1} against #{file2}"
      cmd="#{exec_name} #{file1} #{file2}"
    end
    o,s=ext(cmd,{:die=>false,:msg=>"Error running #{exec_name}",:out=>true})
    if o and o.size==0
      true
    else
      false
    end
  end

  def method_missing(meth, *args, &block)
    logi meth.to_s
    if meth.to_s =~ /^lib_comp_(.+)$/
      lib_comp(*args, $1)
    else
      super # You *must* call super if you don't handle the
            # method, otherwise you'll mess up Ruby's method
            # lookup.
    end
  end

  def respond_to?(meth)
    if meth.to_s =~ /^lib_comp_.*$/
      true
    else
      super
    end
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
    #By the time we get here the run output already contains the desired data structure
    runkit
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
      FileUtils.rm(forcebuild)
    end

    # send mail
    suite_name=env.suite._suitename
    email_from=env.suite.email_from
    email_to=env.suite.email_to
    email_subject=env.suite.email_subject
    email_server=env.suite.email_server
    email_ready=true if email_server and email_from and email_to and email_subject
    #logi env.inspect()
    if env.suite._totalfailures > 0

      msg="#{env.suite._totalfailures} TEST(S) OUT OF #{env.suite._totalruns} FAILED\n"
      logmsg="#{env.suite._totalfailures} TEST(S) OUT OF #{env.suite._totalruns} FAILED\n"
      msg<<"\n--------------------- Builds -------------------------------\n"
      logmsg<<"\n--------------------- Builds -------------------------------\n"
      if env.suite._builds and env.suite._builds.length > 0
        env.suite._builds.each do |k,v|
          if v.is_a?(OpenStruct) and v.result
            msg<<"\n#{k}: PASS"
            logmsg<<"\n#{k}: BUILDINFO(#{v.result})"
          else
            msg<<"\n#{k}: FAIL"
            logmsg<<"\n#{k}: ALLINFO(#{v})"
          end
        end
      end

      if not env.suite.build_only
        msg<<"\n--------------------- Runs -------------------------------\n"
        logmsg<<"\n--------------------- Runs -------------------------------\n"
        if env.suite._runs and env.suite._runs.length > 0
          env.suite._runs.each do |k,v|
            if v.is_a?(OpenStruct) and v.result
              if v.result[:result]
                msg<<"\n#{k}: PASS"
              else
                msg<<"\n#{k}: FAIL"
              end
              logmsg<<"\n#{k}: RUNINFO(#{v.result[:result]} | #{v.result[:laststep]} | #{v.result[:pipeline]} | \"#{v.result[:message]}\") | BUILDINFO(#{v.result[:build]})"
            else
              msg<<"\n#{k}: FAIL"
              logmsg<<"\n#{k}: ALLINFO(#{v})"
            end
          end
        end
      end
      msg<<"\n----------------------------------------------------\n"
      msg<<"See log: #{logfile()}\n"
      logi logmsg
      subject="#{email_subject} -- #{suite_name} (FAILED)"
      send_email(email_from,email_to,subject,email_server,msg,false) if email_ready
    else
      msg="ALL TESTS PASSED\n"
      logmsg="ALL TESTS PASSED\n"
      msg<<"\n--------------------- Builds -------------------------------\n"
      logmsg<<"\n--------------------- Builds -------------------------------\n"
      if env.suite._builds and env.suite._builds.length > 0
        env.suite._builds.each do |k,v|
          if v.is_a?(OpenStruct) and v.result
            msg<<"\n#{k}: PASS"
            logmsg<<"\n#{k}: BUILDINFO(#{v.result})"
          else
            msg<<"\n#{k}: FAIL"
            logmsg<<"\n#{k}: ALLINFO(#{v})"
          end
        end
      end

      if not env.suite.build_only
        msg<<"\n--------------------- Runs -------------------------------\n"
        logmsg<<"\n--------------------- Runs -------------------------------\n"
        if env.suite._runs and env.suite._runs.length > 0
          env.suite._runs.each do |k,v|
            if v.is_a?(OpenStruct) and v.result
              if v.result[:result]
                msg<<"\n#{k}: PASS"
              else
                msg<<"\n#{k}: FAIL"
              end
              logmsg<<"\n#{k}: RUNINFO(#{v.result[:pipeline]} | \"#{v.result[:message]}\") | BUILDINFO(#{v.result[:build]})"
            else
              msg<<"\n#{k}: FAIL"
              logmsg<<"\n#{k}: ALLINFO(#{v})"
            end
          end
        end
      end
      msg<<"\n----------------------------------------------------\n"
      msg<<"See log: #{logfile()}\n"
      logi logmsg
      subject="#{email_subject} -- #{suite_name} (COMPLETED)"
      send_email(email_from,email_to,subject,email_server,msg,false) if email_ready
    end
  end

end

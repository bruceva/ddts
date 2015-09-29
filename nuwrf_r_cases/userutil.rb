require 'net/smtp'
require 'open3'
require 'time'

puts "Loading userutil.rb"

module Userutil

  # *************************************************************
  # CUSTOM METHODS (NOT CALLED BY DRIVER)

  def userutil_version()
    1.0
  end

  #Returns array of date hashes containing year month day 0 padded,
  #between 'from' and 'to' dates of Time type.  Note step is number of seconds.
  # ex: getDateArray(Time.utc(2000,1,1),Time.utc(2000,1,5),60*60*24)
  ##############################################################################
  def getDateArray(from,to,step)
    temp=from
    result=Array.new
    while to >= temp do
      elt={'year'=>temp.strftime("%Y"),'month'=>temp.strftime("%m"),'day'=>temp.strftime("%d"),'dayofyear'=>temp.strftime("%j")}
      result<<elt
      temp = temp + step
    end
    result
  end

  #Creates an Ftp script content assuming you have a hash data structure with year,month,day and set (hash) of associated
  # sites, paths and filenames
  ##############################################################################
  def createFtpScript(data)
    header=<<-eos
#!/bin/bash
# Ftp script for date: #{data["year"]}-#{data["month"]}-#{data["day"]}
# ------------------------------------
eos

    body=""
    data["set"].keys.each do |k|
      site=data["set"][k]["site"]
      path=data["set"][k]["path"]
      filename=data["set"][k]["filename"]
      decompress=data["set"][k]["decompress"]
      temp=<<-eos

# *** data set #{k} ****

if wget -nc "#{site}/#{path}/#{filename}" ; then
  echo "Downloaded #{filename}"
else
  echo "Error downloading #{filename}"
  exit 1
fi
eos
      body<<temp

      if decompress
      
        temp=<<-eos
if #{decompress} #{filename} ; then
  echo "Decompressed  #{filename}"
else
  echo "Error decompressing #{filename}"
  exit 1
fi
eos

      body<<temp
      end

    end

    header+body
  end

  ##############################################################################
  def getMERRADailysetTemplate()
    result=Array.new
    elt={"setname"=>"const_2d_asm_Nx","filename"=>"MERRA300.prod.assim.${setname}.00000000.hdf",
         "site"=>"ftp://goldsmr2.sci.gsfc.nasa.gov","path"=>"data/s4pa//MERRA_MONTHLY/MAC0NXASM.5.2.0/1979"}
    result<<elt
    elt={"setname"=>"inst6_3d_ana_Nv","filename"=>"${merraname}.prod.assim.${setname}.${year}${month}${day}.hdf",
         "site"=>"ftp://goldsmr3.sci.gsfc.nasa.gov","path"=>"data/s4pa/MERRA/MAI6NVANA.5.2.0/${year}/${month}"}
    result<<elt    
    elt={"setname"=>"inst6_3d_ana_Np","filename"=>"${merraname}.prod.assim.${setname}.${year}${month}${day}.hdf",
         "site"=>"ftp://goldsmr3.sci.gsfc.nasa.gov","path"=>"data/s4pa/MERRA/MAI6NPANA.5.2.0/${year}/${month}"}
    result<<elt
    elt={"setname"=>"tavg1_2d_slv_Nx","filename"=>"${merraname}.prod.assim.${setname}.${year}${month}${day}.hdf",
         "site"=>"ftp://goldsmr2.sci.gsfc.nasa.gov","path"=>"data/s4pa/MERRA/MAT1NXSLV.5.2.0/${year}/${month}"}
    result<<elt
    elt={"setname"=>"tavg1_2d_ocn_Nx","filename"=>"${merraname}.prod.assim.${setname}.${year}${month}${day}.hdf",
         "site"=>"ftp://goldsmr2.sci.gsfc.nasa.gov","path"=>"data/s4pa/MERRA/MAT1NXOCN.5.2.0/${year}/${month}"}
    result<<elt
    result
  end

  ##############################################################################
  def getSSTDailysetTemplate()
    result=Array.new
    elt={"setname"=>"sst_remss_${instrument}","ver"=>"v04.0","suffix"=>"${ver}.gz",
         "filename"=>"${instrument}.fusion.${year}.${dayofyear}.${suffix}",
         "site"=>"ftp://data.remss.com","path"=>"sst/daily_${ver}/${instrument}/${year}",
         "decompress"=>"gunzip"}
    result<<elt
    result
  end

  ##############################################################################
  def addSSTDailysetMetadata(dates,settemplate,scriptprefix,instrument)
    dates.each do |elt|
      datelabel="#{elt['year']}#{elt['month']}#{elt['day']}"
      elt["scriptfile"]="#{scriptprefix}_#{datelabel}.bash"
      if settemplate
        if not elt["set"]
           elt["set"]=Hash.new
        end
        settemplate.each do |s|
          ver=s["ver"]
          site=s["site"]
          elt["set"][instrument]=Hash.new
          if s["decompress"]
            elt["set"][instrument].merge!({"decompress"=>s["decompress"]})
          end
          #setname substitutions
          setname=String.new(s["setname"])
          setname.gsub!("${instrument}",instrument)
          #suffix substitutions
          suffix=String.new(s["suffix"])
          suffix.gsub!("${ver}",ver)
          #start with filename template and perform substitutions
          #Note: must be a string copy since substitutions are in place.
          filename=String.new(s["filename"])
          filename.gsub!("${instrument}",instrument)
          filename.gsub!("${year}",elt["year"])
          filename.gsub!("${dayofyear}",elt["dayofyear"])          
          filename.gsub!("${suffix}",suffix)
          #start with path template and perform substitutions
          path=String.new(s["path"])
          path.gsub!("${ver}",ver)
          path.gsub!("${instrument}",instrument)
          path.gsub!("${year}",elt["year"])
          elt["set"][instrument].merge!({"namelistfile"=>"namelist.#{scriptprefix}_#{instrument}_#{datelabel}",
                                  "setname"=>setname,"ver"=>ver,"site"=>site,"filename"=>filename,"path"=>path})                
        end
      end
    end
  end

  ##############################################################################
  def addMERRADailysetMetadata(dates,settemplate,scriptprefix)
    dates.each do |elt| 
      merraname=""
      if elt["year"].to_i < 1993 ; merraname="MERRA100" ; end
      if elt["year"].to_i > 1992 and elt["year"].to_i < 2001 ; merraname="MERRA200" ; end
      if elt["year"].to_i > 2000 ; merraname="MERRA300" ; end
      datelabel="#{elt['year']}#{elt['month']}#{elt['day']}"
      elt["namelistfile"]="namelist.#{scriptprefix}_#{datelabel}"
      elt["scriptfile"]="#{scriptprefix}_#{datelabel}.bash"
      if settemplate
        elt["set"]=Hash.new
        settemplate.each do |s|
          setname=s["setname"]
          site=s["site"]
          #start with filename template and perform substitutions
          #Note: must be a string copy since substitutions are in place.
          filename=String.new(s["filename"])
          filename.gsub!("${setname}",setname)
          filename.gsub!("${merraname}",merraname)
          filename.gsub!("${year}",elt["year"])
          filename.gsub!("${month}",elt["month"])
          filename.gsub!("${day}",elt["day"])
          #start with path template and perform substitutions
          path=String.new(s["path"])
          path.gsub!("${year}",elt["year"])
          path.gsub!("${month}",elt["month"])
          path.gsub!("${day}",elt["day"])          
          elt["set"][setname]={"site"=>site,"filename"=>filename,"path"=>path}
        end
      end
    end
  end 

# Creates the namelist from the data structure w/metadata of a single date.
  ##############################################################################
  def createMERRANamelist(data)

    result=<<-eos
! MERRA namelist file: #{data["namelistfile"]}
!------------------------------------
&input

  ! Directory to write output
  outputDirectory = '.',

  ! Directory with input MERRA files
  merraDirectory = '.',

  ! Format and name of const_2d_asm_Nx file
  merraFormat_const_2d_asm_Nx = 4,
  merraFile_const_2d_asm_Nx = '#{data["set"]["const_2d_asm_Nx"]["filename"]}',

  ! Number of days to process.  Note that each file type (excluding const_2d_asm_Nx)
  ! will have one file per day.
  numberOfDays = 1,

  ! Dates of each day being processed (YYYY-MM-DD)
  ! ex: merraDate(1) = '2009-08-25',
  merraDates(1) = '#{data["year"]}-#{data["month"]}-#{data["day"]}',

  ! Format and Names of inst6_3d_ana_Nv files.
  merraFormat_inst6_3d_ana_Nv = 4,
  merraFiles_inst6_3d_ana_Nv(1) = '#{data["set"]["inst6_3d_ana_Nv"]["filename"]}',

  ! Names of inst6_3d_ana_Np files.
  merraFormat_inst6_3d_ana_Np = 4,
  merraFiles_inst6_3d_ana_Np(1) = '#{data["set"]["inst6_3d_ana_Np"]["filename"]}',

  ! Names of tavg1_2d_slv_Nx files.
  merraFormat_tavg1_2d_slv_Nx = 4,
  merraFiles_tavg1_2d_slv_Nx(1) = '#{data["set"]["tavg1_2d_slv_Nx"]["filename"]}',

  ! Names of tavg1_2d_ocn_Nx files.
  merraFormat_tavg1_2d_ocn_Nx = 4,
  merraFiles_tavg1_2d_ocn_Nx(1) = '#{data["set"]["tavg1_2d_ocn_Nx"]["filename"]}',

/
eos
  end

# Creates the executes script from the data structure w/metadata of a single date.
  ##############################################################################
  def createMERRAExecuteScript(data)
    result=<<-eos
#!/bin/bash
# MERRA script for date: #{data["year"]}-#{data["month"]}-#{data["day"]}
# ------------------------------------
if [ -f #{data['namelistfile']} ] ; then
  # Run the merra2wrf 
  if ./merra2wrf #{data['namelistfile']} ; then 
    echo 'MERRA2WRF completed successfully for #{data["year"]}-#{data["month"]}-#{data["day"]}' 
  else
    echo 'ERROR: MERRA2WRF failed for #{data["year"]}-#{data["month"]}-#{data["day"]}'  
    exit 1
  fi
else
  echo "ERROR Unable to run merra2wrf: #{data['namelistfile']}  not found"
  exit 1
fi

# Clean the downloaded data files
#rm #{data['set']['inst6_3d_ana_Nv']['filename']} 
#rm #{data['set']['inst6_3d_ana_Np']['filename']}
#rm #{data['set']['tavg1_2d_slv_Nx']['filename']}
#rm #{data['set']['tavg1_2d_ocn_Nx']['filename']}

exit 0

eos
  result
  end

# Creates the namelist from the data structure w/metadata of a single date.
  ##############################################################################
  def createSSTNamelist(data,instrument)
    content=<<-eos
! SST namelist file: #{data["set"][instrument]["namelistfile"]}
!------------------------------------
&input
  instrument = "#{instrument}",
  year = #{data["year"]},
  dayOfYear = #{data["dayofyear"]}, 
  version = "#{data["set"][instrument]["ver"]}",
  inputDirectory = ".",
/
&output 
  outputDirectory = ".",
  prefixWPS = "SSTRSS",
/
&fakeoutput 
  numFakeHours = 4, 
  fakeHours = 0, 6, 12, 18,
/  
eos

  [content,data["set"][instrument]['namelistfile']]
  end

# Creates the executes script from the data structure w/metadata of a single date.
  ##############################################################################
  def createSSTExecuteScript(data)
    result=<<-eos
#!/bin/bash
# SST script for date: #{data["year"]}-#{data["month"]}-#{data["day"]}
# ------------------------------------

eos

    data["set"].keys.each do |instrument|
       step=<<-eos
if [ -f #{data["set"][instrument]['namelistfile']} ] ; then

  rm namelist.sst2wrf
  ln -s #{data["set"][instrument]['namelistfile']} namelist.sst2wrf
  # Run the sst2wrf 
  if ./sst2wrf ; then 
    echo 'sst2wrf completed successfully for #{instrument} #{data["year"]}-#{data["month"]}-#{data["day"]}' 
  else
    echo 'ERROR: sst2wrf failed for #{instrument} #{data["year"]}-#{data["month"]}-#{data["day"]}'  
    exit 1
  fi
else
  echo "ERROR Unable to run sst2wrf: #{data["set"][instrument]['namelistfile']}  not found"
  exit 1
fi

# Clean the downloaded data files

exit 0

eos

    result<<step
    end

  result
  end


  # Edit the lis.config file found in rundir according to the parameters
  # stored in the env data structure
  ##############################################################################
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

  ##############################################################################
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

  ##############################################################################
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
  ##############################################################################
  def deref(run,ref)
    result=run
    ref.split('.').each do |r|
      result=result.send(r) if result
    end
    result 
  end

  #Given an opestruct run,create the list of expected input files
  #for the given processor.
  ##############################################################################
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

  ##############################################################################
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

  ##############################################################################
  def createTypedLinks(env,type)

    script=""

    if type.include?('wrf')
      links=env.run.preprocessor_links.send(type)
      links.each do |l|
        f=File.join('$NUWRFDIR','WRFV3','run',l)
        check=<<-eos
if [ ! -e #{f} ] ; then 
    echo "ERROR, #{f} does not exist!"
    exit 1
fi
eos
        script<<check
        script<<"ln -fs #{f} #{l} || exit 1\n"
      end
    elsif type.include?('lis')
      links=env.run.preprocessor_links.send(type)
      links.each do |l|
        fw=File.join('$WORKDIR',l)
        script<<"rm #{fw}\n"
        f=File.join('$LISDIR',l)
        check=<<-eos
if [ ! -e #{f} ] ; then 
    echo "ERROR, #{f} does not exist!"
    exit 1
fi  
eos
        script<<check
        script<<"ln -fs #{f} #{fw} || exit 1\n"
      end
    elsif type.include?('data')
      links=env.run.preprocessor_links.send(type)
      links.each do |l|
        fw=File.join('$WORKDIR',l)
        script<<"rm #{fw}\n"
        f=File.join('$DATADIR',l)
        check=<<-eos
if [ ! -e #{f} ] ; then 
    echo "ERROR, #{f} does not exist!"
    exit 1
fi  
eos
        script<<check
        script<<"ln -fs #{f} #{fw} || exit 1\n"
      end
    elsif type.include?('WRFV3')
      links=env.run.preprocessor_links.send(type)
      links.each do |l|
        fw=File.join('$WORKDIR',l)
        script<<"rm #{fw}\n"
        f=File.join('$NUWRFDIR','WRFV3',l)
        check=<<-eos
if [ ! -e #{f} ] ; then 
    echo "ERROR, #{f} does not exist!"
    exit 1
fi  
eos
        script<<check
        script<<"ln -fs #{f} #{fw} || exit 1\n"
      end
    elsif type.include?('utils')
      links=env.run.preprocessor_links.send(type)
      links.each do |l|
        namesource=namelink=""
        if l.size == 2
          namesource=l[0]
          namelink=l[1]
        else
          namesource=namelink=l
        end 
        fw=File.join('$WORKDIR',namelink)
        script<<"rm #{fw}\n"
        fs=File.join('$NUWRFDIR','utils',namesource)
        check=<<-eos
if [ ! -e #{fs} ] ; then 
    echo "ERROR, #{fs} does not exist!"
    exit 1
fi  
eos
        script<<check
        script<<"ln -fs #{fs} #{fw} || exit 1\n"
      end
    elsif type.include?('local_links') 
      links=env.run.preprocessor_links.send(type)
      links.each do |lk|
        if lk.size == 2
          #First item is the file path relative to the working directory 
          fw=File.join('$WORKDIR',lk[0])
          #Second item is the link name relative ot the working directory
          fl=File.join('$WORKDIR',lk[1])
          if fw != fl
        check=<<-eos
if [ ! -e #{fw} ] ; then 
    echo "ERROR, #{fw} does not exist!"
    exit 1
fi  
eos
            script<<check
            script<<"ln -fs #{fw} #{fl} || exit 1\n"  
          else
            logw ("File and link are identical  in #{type} YAML definiton")
          end      
        else
          logw ("Incomplete link pair in #{type} YAML definition")
        end
      end
    elsif type.include?('check_exist')
      links=env.run.preprocessor_links.send(type)
      links.each do |lk|
        fw=File.join('$WORKDIR',lk)
        check=<<-eos
if [ ! -e #{fw} ] ; then 
    echo "ERROR, #{fw} does not exist!"
    exit 1
fi  

eos
        script<<check
      end
    end

    script
  end

  ##############################################################################
  def createCommonPreprocessorScript(env,rundir)

    loadModules=env.run.modules.send(env.run.compiler)
    batchExports=env.run.batch_exports.send(env.run.compiler)
  
    script=<<-eos
#!/bin/bash

# --- shared script used by specific preprocessor scripts ----

source /usr/share/modules/init/sh
module purge

unset LD_LIBRARY_PATH

module load #{loadModules}

# Make sure stacksize is unlimited
ulimit -s unlimited

export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/lib64

# Define locations of LIS, NUWRF, and the experiment work directory
LDTDIR=#{env.build.ddts_root}/ldt
LISDIR=#{env.run.lis_dir}
NUWRFDIR=#{env.build.ddts_root}
WORKDIR=#{rundir}
DATADIR=#{env.run.baselinedir}

# Set environment variables needed by RIP
export RIP_ROOT=$NUWRFDIR/RIP4
eos

    batchExports.each { |expo| script << "export #{expo}\n"}

    script
  end

  ##############################################################################
  def lib_re_str_job_id
    '(\d+).*'
  end

  ##############################################################################
  def lib_submit_script
    'sbatch'
  end

  ##############################################################################
  def batch_filename(env)
    "runWrf_#{env.run.proc_id}.job"
  end

  ##############################################################################
  def createPreprocessorHeader(env, preprocessor)

    script="#!/bin/bash\n"
    if "#{env.run.submission_type.send(preprocessor)}" == "batch"
      script<<"# *** Note: Batch job script ***\n"
      script<<"#SBATCH -J #{env.run.batch_name.send(preprocessor)}\n"
      script<<"#SBATCH -t #{env.run.batch_time.send(preprocessor)}\n"
      script<<"#SBATCH -A #{env.run.batch_group.send(preprocessor)}\n"
      script<<"#SBATCH -o #{env.run.batch_slurmout.send(preprocessor)}\n"
      if env.run.batch_queue.send(preprocessor) != ''
         script<<"#SBATCH -p #{env.run.batch_queue.send(preprocessor)}\n"
      end
      proclineid=env.run.batch_procline.send(preprocessor)
      if env.run.proc_line.send(proclineid)
        script<<"#SBATCH -N #{env.run.proc_line.send(proclineid)}\n"
      else
        logw "Unable to locate an entry for #{proclineid} in proc_line" 
      end
    else
      script<<"# *** Note: Local job script  ***\n"
    end
    script<<"\n#---------------------- #{preprocessor} script -----------------------------\n\n"  

    script
  end

  ##############################################################################
  def createCommonPreprocessorBody(env, preprocessor, namelist=nil)

    script=nil
    if env.run.submission_type.send(preprocessor) == 'batch'
      script=<<-eos
# Change to the directory where job was submitted.
if [ ! -z $SLURM_SUBMIT_DIR ] ; then
    cd $SLURM_SUBMIT_DIR || exit 1
fi
eos
    end

    script2=<<-eos
# Load config file for modules and paths
source ./common.bash || exit 1

if [ -z "$NUWRFDIR" ] ; then
    echo "ERROR, NUWRFDIR is not defined!"
    exit 1
fi

# Move to work directory
if [ -z "$WORKDIR" ] ; then
    echo "ERROR, WORKDIR is not defined!"
    exit 1
fi

cd $WORKDIR || exit 1

eos

    script3=nil
    if namelist

      script3=<<-eos
# make sure #{namelist} is present.
if [ ! -e #{namelist} ] ; then
    echo "ERROR, #{namelist} not found!"
    exit 1
fi

eos
    end

    # Assemble the result
    result=""
    if script
      result<<script
    end
    if script2
      result<<script2
    end
    if script3
      result<<script3
    end

    result
  end

  ##############################################################################
  def createLdtLinks(env,var_select)
    script=""
    if env.run.send(var_select) and env.run.send(var_select).class == Array
      env.run.send(var_select).each do |type|
        script<<createTypedLinks(env,type)
      end
    elsif env.run.send(var_select)
      script<<createTypedLinks(env,env.run.send(var_select))
    end
    script
  end

  ##############################################################################
  def createLdtPrelisPreprocessorScript(env,scriptout)

    header=createPreprocessorHeader(env,'ldt_prelis')

    body=createCommonPreprocessorBody(env,'ldt_prelis','ldt.config.prelis')

    body<<createLdtLinks(env,'ldt_prelis_select')

    footer=<<-eos

rm ldt.config
ln -s ldt.config.prelis ldt.config || exit 1

# Run LDT
ln -fs $LDTDIR/LDT LDT || exit 1
if [ ! -e LDT ] ; then 
    echo "ERROR, LDT does not exist!"
    exit 1
fi

# Execute
mpirun -np $SLURM_NTASKS ./LDT ldt.config > #{scriptout}

# The end
exit 0
eos

  header+body+footer

  end

  ##############################################################################
  def createLisPreprocessorScript(env,scriptout)

    header=createPreprocessorHeader(env,'lis')

    body=createCommonPreprocessorBody(env,'lis','lis.config.prewrf')

    body<<createLdtLinks(env,'lis_select')

    footer=<<-eos

rm lis.config
ln -s lis.config.prewrf lis.config || exit 1

# Run LIS
ln -fs $NUWRFDIR/WRFV3/lis/make/LIS $WORKDIR/LIS || exit 1
if [ ! -e $WORKDIR/LIS ] ; then 
    echo "ERROR, $WORKDIR/LIS does not exist!"
    exit 1
fi

# Execute
mpirun -np $SLURM_NTASKS ./LIS lis.config > #{scriptout}

# Tidy up logs
mkdir -p lis_logs || exit 1

mv lislog.* lis_logs

# The end
exit 0
eos

  header+body+footer

  end


  ##############################################################################
  def createLdtPostlisPreprocessorScript(env,scriptout)

    header=createPreprocessorHeader(env,'ldt_postlis')

    body=createCommonPreprocessorBody(env,'ldt_postlis','ldt.config.postlis')

    body<<createLdtLinks(env,'ldt_postlis_select')

    footer=<<-eos

rm ldt.config
ln -s ldt.config.postlis ldt.config || exit 1

# Run LDT
ln -fs $LDTDIR/LDT LDT || exit 1
if [ ! -e LDT ] ; then 
    echo "ERROR, LDT does not exist!"
    exit 1
fi

# Execute
mpirun -np $SLURM_NTASKS ./LDT ldt.config > #{scriptout}

# The end
exit 0
eos

  header+body+footer

  end

  ##############################################################################
  def createGeogridLinks(env)

    script=<<-eos
# Put geogrid TBL look-up file into geogrid subdirectory

if [ -e geogrid ] ; then
    rm -rf geogrid || exit 1
fi
mkdir -p geogrid || exit 1

eos
    links=env.run.preprocessor_links.send(env.run.geogrid_select)
    f=File.join('$NUWRFDIR','WPS','geogrid',links[0])
    l=File.join('geogrid',links[1])
    script<<"ln -fs #{f} #{l} || exit 1\n" 

    check=<<-eos
if [ ! -e geogrid/#{links[1]} ] ; then 
    echo "ERROR, geogrid/#{links[1]} does not exist!"
    exit 1
fi
eos
    script+check
  end


  ##############################################################################
  def createGeogridPreprocessorScript(env)

    header=createPreprocessorHeader(env,'geogrid')
  
    body=createCommonPreprocessorBody(env,'geogrid','namelist.wps')

    body<<createGeogridLinks(env)

    footer=<<-eos
# Run geogrid.exe
ln -fs $NUWRFDIR/WPS/geogrid/src/geogrid.exe geogrid.exe || exit 1
if [ ! -e geogrid.exe ] ; then 
    echo "ERROR, geogrid.exe does not exist!"
    exit 1
fi
mpirun -np $SLURM_NTASKS ./geogrid.exe || exit 1

# Tidy up logs
mkdir -p geogrid_logs || exit 1

mv geogrid.log.* geogrid_logs

# The end
exit 0
eos

    header+body+footer
  end

  ##############################################################################
  def getUngribInputVtable(env)
    links=env.run.preprocessor_links.send(env.run.ungrib_select)
    links[0]
  end

  ##############################################################################
  def getUngribInputVtableLink(env)
    links=env.run.preprocessor_links.send(env.run.ungrib_select)
    links[1]
  end

  ##############################################################################
  def getUngribInputPattern(env)
    links=env.run.preprocessor_links.send(env.run.ungrib_select)
    links[3]
  end

  ##############################################################################
  def getUngribInputLinkDir(env)
    links=env.run.preprocessor_links.send(env.run.ungrib_select)
    links[2]
  end

  ##############################################################################
  def getGocart2wrfInputPattern(env)
    links=env.run.preprocessor_links.send(env.run.gocart2wrf_select)[0]
    links[1]
  end

  ##############################################################################
  def getGocart2wrfInputLinkDir(env)
    links=env.run.preprocessor_links.send(env.run.gocart2wrf_select)[0]
    links[0]
  end

  ##############################################################################
  def getInputPattern (env,prep)
    if prep == 'ungrib'
      getUngribInputPattern(env)
    elsif prep == 'gocart2wrf'
      getGocart2wrfInputPattern(env)
    elsif prep == 'geos2wrf'
      "*"
    #elsif prep == 'geos2wrf_merra2'
    #  "*"
    elsif prep == 'prep_chem_sources'
      "*"
    else
      die ("#{prep} does not have a corresponding input pattern")
    end
  end

  ##############################################################################
  def getInputLinkDir(env,prep)
    if prep == 'ungrib'
      getUngribInputLinkDir(env)
    elsif prep == 'gocart2wrf'
      getGocart2wrfInputLinkDir(env)
    elsif prep == 'geos2wrf'
      '.'
    #elsif prep == 'geos2wrf_merra2'
    #  '.'
    elsif prep == 'prep_chem_sources'
      '.'
    else
      die ("#{prep} does not have an associated input link directory")
    end
  end

  ##############################################################################
  def createUngribLinks(env)

    l=getUngribInputVtableLink(env)

    script=<<-eos
# Make sure #{l} is present.
# NOTE:  User may need to change source #{l} name depending on their data
# source.

if [ -e #{l} ] ; then
    rm -f #{l} || exit 1
fi
eos

    f=File.join('$NUWRFDIR','WPS','ungrib','Variable_Tables',getUngribInputVtable(env))
    script<<"ln -fs #{f} #{l} || exit 1\n"
    
    check=<<-eos
if [ ! -e #{l} ] ; then 
    echo "ERROR, #{l} does not exist!"
    exit 1
fi
eos
    script<<check

    script2=<<-eos
# Create GRIBFILE symbolic links to grib files.
# NOTE:  User may need to change the grib file prefix depending on their
# data source.
ln -fs $NUWRFDIR/WPS/link_grib.csh link_grib.csh || exit 1
if [ ! -e link_grib.csh ] ; then
    echo "ERROR, link_grib.csh does not exist!"
    exit 1
fi

./link_grib.csh #{getUngribInputPattern(env)} || exit 1
eos

    script+script2
  end

  ##############################################################################
  def createUngribPreprocessorScript(env)

    header=createPreprocessorHeader(env,'ungrib')

    body=createCommonPreprocessorBody(env,'ungrib','namelist.wps')

    body<<createUngribLinks(env)

    footer=<<-eos
# Run ungrib.exe.  No MPI is used since the program is serial.
ln -fs $NUWRFDIR/WPS/ungrib/src/ungrib.exe ungrib.exe || exit 1
if [ ! -e ungrib.exe ] ; then
    echo "ERROR, ungrib.exe does not exist!"
    exit 1
fi

./ungrib.exe >& ungrib_out.log || exit 1

# Tidy up logs
mkdir -p ungrib_logs || exit 1

mv ungrib_out.log ungrib_logs
mv ungrib.log ungrib_logs

# The end
exit 0
eos

    header+body+footer
  end

  ##############################################################################
  def createFTPSstPreprocessorScript(env)

    header=createPreprocessorHeader(env,'ftp_sst')

    body=createCommonPreprocessorBody(env,'ftp_sst')

    #Express start and end dates in terms of Time objects
    date_start=Time.utc(env.run.sst_dates.start.year,env.run.sst_dates.start.month,env.run.sst_dates.start.day)
    date_end=Time.utc(env.run.sst_dates.end.year,env.run.sst_dates.end.month,env.run.sst_dates.end.day)
    #Calculate a day in seconds for the interval
    interval=60*60*24
    #Initialize the sst data structure with the dates
    sst_data=getDateArray(date_start,date_end,interval)
    #Add the metadata to the data structure as dictated by the template
    env.run.sst_instrument.each do |instr|
      addSSTDailysetMetadata(sst_data,getSSTDailysetTemplate(),"ftp_sst",instr)
    end

    #Create one ftp script per day
    rundir=env.run.ddts_root
    scripts_to_run =""
    sst_data.each do |data|
      content=createFtpScript(data)
      fileName = File.join(rundir,data["scriptfile"])
      File.open(fileName, "w+") do |scriptFile|
        scriptFile.print(content)
        logd "Created script file: #{fileName}"
        FileUtils.chmod(0754,fileName,:verbose=>true)
      end
      scripts_to_run<<data["scriptfile"]+" "
    end

    #Finalize main driver script
    footer=<<-eos

for file in #{scripts_to_run} ; do
   
  if ! ./$file >> ftpsst.log 2>&1 ; then
    exit 1
  fi

done

echo "Successful SST ftp processing" >> ftpsst.log

# Tidy up logs
mkdir -p ftpsst_logs || exit 1

mv ftpsst.log ftpsst_logs

exit 0
   
eos

    header+body+footer

  end


  ##############################################################################
  def createFTPMerraPreprocessorScript(env)

    header=createPreprocessorHeader(env,'ftp_merra')

    body=createCommonPreprocessorBody(env,'ftp_merra')

    #Express start and end dates in terms of Time objects
    date_start=Time.utc(env.run.merra_dates.start.year,env.run.merra_dates.start.month,env.run.merra_dates.start.day)
    date_end=Time.utc(env.run.merra_dates.end.year,env.run.merra_dates.end.month,env.run.merra_dates.end.day)
    #Calculate a day in seconds for the interval
    interval=60*60*24
    #Initialize the merra data structure with the dates
    merra_data=getDateArray(date_start,date_end,interval)
    #Add the metadata to the data structure as dictated by the template
    addMERRADailysetMetadata(merra_data,getMERRADailysetTemplate(),"ftp_merra")
    
    #Create one ftp script per day
    rundir=env.run.ddts_root
    scripts_to_run =""
    merra_data.each do |data|
      content=createFtpScript(data)
      fileName = File.join(rundir,data["scriptfile"])
      File.open(fileName, "w+") do |scriptFile|
        scriptFile.print(content)
        logd "Created script file: #{fileName}"
        FileUtils.chmod(0754,fileName,:verbose=>true)
      end
      scripts_to_run<<data["scriptfile"]+" "
    end
   
    #Finalize main driver script
    footer=<<-eos

for file in #{scripts_to_run} ; do
   
  if ! ./$file >> ftpmerra.log 2>&1 ; then
    exit 1
  fi

done

echo "Successful MERRA ftp processing" >> ftpmerra.log

# Tidy up logs
mkdir -p ftpmerra_logs || exit 1

mv ftpmerra.log ftpmerra_logs

exit 0
   
eos

    header+body+footer

  end

  ##############################################################################
  def createMerra2wrfPreprocessorScript(env)

    header=createPreprocessorHeader(env,'merra2wrf')

    body=createCommonPreprocessorBody(env,'merra2wrf')

    #Express start and end dates in terms of Time objects
    date_start=Time.utc(env.run.merra_dates.start.year,env.run.merra_dates.start.month,env.run.merra_dates.start.day)
    date_end=Time.utc(env.run.merra_dates.end.year,env.run.merra_dates.end.month,env.run.merra_dates.end.day)
    #Calculate a day in seconds for the interval
    interval=60*60*24
    #Initialize the merra data structure with the dates
    merra_data=getDateArray(date_start,date_end,interval)
    #Add the metadata to the data structure as dictated by the template
    addMERRADailysetMetadata(merra_data,getMERRADailysetTemplate(),"merra2wrf")

    #Create one ftp script per day
    rundir=env.run.ddts_root
    scripts_to_run =""
    merra_data.each do |data|
      #Create the daily script file
      content=createMERRAExecuteScript(data)
      fileName = File.join(rundir,data["scriptfile"])
      File.open(fileName, "w+") do |scriptFile|
        scriptFile.print(content)
        logd "Created script file: #{fileName}"
        FileUtils.chmod(0754,fileName,:verbose=>true)
      end
      scripts_to_run<<data["scriptfile"]+" "

      #Create the required namelist file
      content=createMERRANamelist(data)
      fileName = File.join(rundir,data["namelistfile"])
      File.open(fileName, "w+") do |nlFile|
        nlFile.print(content)
        logd "Created file: #{fileName}"
      end

    end

    #Finalize main driver script
    footer=<<-eos

ln -fs $NUWRFDIR/utils/geos2wrf_2/merra2wrf  || exit 1
if [ ! -e merra2wrf ] ; then
    echo "ERROR, merra2wrf not found!"
    exit 1
fi

for file in #{scripts_to_run} ; do
   
  ./$file >> merra2wrf.log 2>&1 || exit 1

done

echo "Successful MERRA2WRF processing" >> merra2wrf.log

# Tidy up logs
mkdir -p merra2wrf_logs || exit 1

mv merra2wrf.log merra2wrf_logs

exit 0
   
eos

    header+body+footer

  end

  ##############################################################################
  def createRunMerraLinks(env)
    script=""
    if env.run.run_merra_select and env.run.run_merra_select.class == Array
      env.run.run_merra_select.each do |type|
        script<<createTypedLinks(env,type)
      end
    elsif env.run.run_merra_select
      script<<createTypedLinks(env,env.run.run_merra_select)
    end
    script
  end

  ##############################################################################
  def createRunMerraPreprocessorScript(env)

    header=createPreprocessorHeader(env,'run_merra')

    body=createCommonPreprocessorBody(env,'run_merra')

    body<<createRunMerraLinks(env)

    footer=<<-eos

ln -fs $NUWRFDIR/utils/geos2wrf_2/merra2wrf  || exit 1
if [ ! -e merra2wrf ] ; then
    echo "ERROR, merra2wrf not found!"
    exit 1
fi

#Run script
if [ -e Run_MERRA.csh ] ; then
    chmod +x Run_MERRA.csh
    ./Run_MERRA.csh #{env.run.merra_dates.start} #{env.run.merra_dates.end} . $NUWRFDIR >& runmerra.log || exit
elif [ -e Run_MERRA2.csh ] ; then
    chmod +x Run_MERRA2.csh
    ./Run_MERRA2.csh #{env.run.merra_dates.start} #{env.run.merra_dates.end} . $NUWRFDIR >& runmerra.log || exit
else
    echo "ERROR, Run_MERRA[2].csh does not exist!"
    exit 1
fi

# Tidy up logs
mkdir -p runmerra_logs || exit 1
mv runmerra.log runmerra_logs

# end
exit 0

eos
    header+body+footer
  end

  ##############################################################################
  def createSst2wrfLinks(env)
    script=""
    if env.run.sst2wrf_select and env.run.sst2wrf_select.class == Array
      env.run.sst2wrf_select.each do |type|
        script<<createTypedLinks(env,type)
      end
    elsif env.run.sst2wrf_select
      script<<createTypedLinks(env,env.run.sst2wrf_select)
    end
    script
  end

  ##############################################################################
  def createSst2wrfPreprocessorScript(env)

    header=createPreprocessorHeader(env,'sst2wrf')

    body=createCommonPreprocessorBody(env,'sst2wrf')

    body<<createSst2wrfLinks(env)

    #Express start and end dates in terms of Time objects
    date_start=Time.utc(env.run.sst_dates.start.year,env.run.sst_dates.start.month,env.run.sst_dates.start.day)
    date_end=Time.utc(env.run.sst_dates.end.year,env.run.sst_dates.end.month,env.run.sst_dates.end.day)
    #Calculate a day in seconds for the interval
    interval=60*60*24
    #Initialize the sst data structure with the dates
    sst_data=getDateArray(date_start,date_end,interval)
    #Add the metadata to the data structure as dictated by the template
    env.run.sst_instrument.each do |instr|
      addSSTDailysetMetadata(sst_data,getSSTDailysetTemplate(),"sst2wrf",instr)
    end

    #Create one sst2wrf script per day
    rundir=env.run.ddts_root
    scripts_to_run =""
    sst_data.each do |data|
      
      content=createSSTExecuteScript(data)
      fileName = File.join(rundir,data["scriptfile"])
      File.open(fileName, "w+") do |scriptFile|
        scriptFile.print(content)
        logd "Created script file: #{fileName}"
        FileUtils.chmod(0754,fileName,:verbose=>true)
      end
      scripts_to_run<<data["scriptfile"]+" "

      #Create the required namelist file
      env.run.sst_instrument.each do |instr|
        content,name=createSSTNamelist(data,instr)
        fileName = File.join(rundir,name)
        File.open(fileName, "w+") do |nlFile|
          nlFile.print(content)
          logd "Created file: #{fileName}"
        end
      end
    end

    #Finalize main driver script
    footer=<<-eos

for file in #{scripts_to_run} ; do
   
  if ! ./$file >> sst2wrf.log 2>&1 ; then
    exit 1
  fi

done

echo "Successful sst2wrf processing" >> sst2wrf.log

# Tidy up logs
mkdir -p sst2wrf_logs || exit 1

mv sst2wrf.log sst2wrf_logs

exit 0
   
eos

    header+body+footer

  end


  ##############################################################################
  def createRunSstLinks(env)
    script=""
    if env.run.run_sst_select and env.run.run_sst_select.class == Array
      env.run.run_sst_select.each do |type|
        script<<createTypedLinks(env,type)
      end
    elsif env.run.run_sst_select
      script<<createTypedLinks(env,env.run.run_sst_select)
    end
    script
  end

  ##############################################################################
  def createRunSstPreprocessorScript(env)

    header=createPreprocessorHeader(env,'run_sst')

    body=createCommonPreprocessorBody(env,'run_sst')

    body<<createRunSstLinks(env)

    footer=<<-eos

#Run script
if [ ! -e Run_SST.csh ] ; then
    echo "ERROR, Run_SST.csh does not exist!"
    exit 1
fi

chmod +x Run_SST.csh

./Run_SST.csh #{env.run.sst_dates.start} #{env.run.sst_dates.end} #{env.run.sst_instrument} . $NUWRFDIR >& runsst.log || exit

# Tidy up logs
mkdir -p runsst_logs || exit 1
mv runsst.log runsst_logs

# end
exit 0

eos
    header+body+footer
  end


  ##############################################################################
  def createGeos2wrfLinks(env)
    script=""
    if env.run.geos2wrf_select and env.run.geos2wrf_select.class == Array
      env.run.geos2wrf_select.each do |type|
        script<<createTypedLinks(env,type)
      end
    elsif env.run.geos2wrf_select
      script<<createTypedLinks(env,env.run.geos2wrf_select)
    end
    script
  end
 
 
  ##############################################################################
  def createGeos2wrfPreprocessorScript(env)
    header=createPreprocessorHeader(env,'geos2wrf')
    body=createCommonPreprocessorBody(env,'geos2wrf','namelist.wps')

    body<<createGeos2wrfLinks(env)

    footer=<<-eos

ln -fs $NUWRFDIR/utils/geos2wrf_2/geos2wps  || exit 1
if [ ! -e geos2wps ] ; then
    echo "ERROR, geos2wps not found!"
    exit 1
fi

ln -fs $NUWRFDIR/utils/geos2wrf_2/createSOILHGT  || exit 1
if [ ! -e createSOILHGT ] ; then
    echo "ERROR, createSOILHGT not found!"
    exit 1
fi

ln -fs $NUWRFDIR/utils/geos2wrf_2/createLANDSEA  || exit 1
if [ ! -e createLANDSEA ] ; then
    echo "ERROR, createLANDSEA not found!"
    exit 1
fi

ln -fs $NUWRFDIR/utils/geos2wrf_2/createRH  || exit 1
if [ ! -e createRH ] ; then
    echo "ERROR, createRH not found!"
    exit 1
fi

#Run script
if [ -e c1440_NR.geos2wrf.py ] ; then
    ./c1440_NR.geos2wrf.py c1440_NR.geos2wrf.settings.cfg c1440_NR.geos2wrf.variables.cfg >& geos2wrf.log || exit
    
elif [ -e $WORKDIR/run_geos2wrf_merra2_3hrassim.discover.sh ] ; then
    chmod +x $WORKDIR/run_geos2wrf_merra2_3hrassim.discover.sh
    $WORKDIR/run_geos2wrf_merra2_3hrassim.discover.sh >& $WORKDIR/geos2wrf.log || exit

elif [ -e $WORKDIR/run_temporalInterpolation_merra2_3hr.discover.sh ] ; then
    chmod +x $WORKDIR/run_temporalInterpolation_merra2_3hr.discover.sh
    $WORKDIR/run_temporalInterpolation_merra2_3hr.discover.sh >& $WORKDIR/geos2wrf.log || exit

else    
    echo "Geos2wrfPreprocessor: ERROR, can't find c1440_NR.geos2wrf.py or run_geos2wrf_merra2_3hrassim.discover.sh or run_temporalInterpolation_merra2_3hr.discover.sh"
    exit 1
fi

echo "Successful completion of program" >> geos2wrf.log

# Tidy up logs
mkdir -p geos2wrf_logs || exit 1
mv geos2wrf.log geos2wrf_logs

# end
exit 0

eos
    header+body+footer
  end
  
  
#  ##############################################################################
#  def createGeos2wrfMerra2Links(env)
#    script=""
#    if env.run.geos2wrf_merra2_select and env.run.geos2wrf_merra2_select.class == Array
#      env.run.geos2wrf_merra2_select.each do |type|
#        script<<createTypedLinks(env,type)
#      end
#    elsif env.run.geos2wrf_merra2_select
#      script<<createTypedLinks(env,env.run.geos2wrf_merra2_select)
#    end
#    script
#  end
# 
# 
#  ##############################################################################
#  def createGeos2wrfMerra2PreprocessorScript(env)
#    header=createPreprocessorHeader(env,'geos2wrf_merra2')
#    body=createCommonPreprocessorBody(env,'geos2wrf_merra2','namelist.wps')
#
#    body<<createGeos2wrfMerra2Links(env)
#
#    footer=<<-eos
#    
#export MERRA2ROOT=$WORKDIR
#
#ln -fs $NUWRFDIR/utils/geos2wrf_2/geos2wps  || exit 1
#if [ ! -e geos2wps ] ; then
#    echo "ERROR, geos2wps not found!"
#    exit 1
#fi
#
#ln -fs $NUWRFDIR/utils/geos2wrf_2/createSOILHGT  || exit 1
#if [ ! -e createSOILHGT ] ; then
#    echo "ERROR, createSOILHGT not found!"
#    exit 1
#fi
#
#ln -fs $NUWRFDIR/utils/geos2wrf_2/createLANDSEA  || exit 1
#if [ ! -e createLANDSEA ] ; then
#    echo "ERROR, createLANDSEA not found!"
#    exit 1
#fi
#
#ln -fs $NUWRFDIR/utils/geos2wrf_2/createRH  || exit 1
#if [ ! -e createRH ] ; then
#    echo "ERROR, createRH not found!"
#    exit 1
#fi
#
#
##Run script
#if [ ! -e run_geos2wrf_merra2_3hrassim.discover.sh ] ; then
#    echo "ERROR, run_geos2wrf_merra2_3hrassim.discover.sh does not exist!"
#    exit 1
#fi
#
#./run_geos2wrf_merra2_3hrassim.discover.sh >& geos2wrf_merra2.log || exit
#
#echo "Successful completion of program" >> geos2wrf_merra2.log
#
## Tidy up logs
#mkdir -p geos2wrf_merra2_logs || exit 1
#mv geos2wrf_merra2.log geos2wrf_merra2_logs
#
## end
#exit 0
#
#eos
#    header+body+footer
#  end
#

  ##############################################################################
  def createMetgridLinks(env)

    script=<<-eos
# Put metgrid TBL look-up file into metgrid subdirectory

if [ -e metgrid ] ; then
    rm -rf metgrid || exit 1
fi
mkdir -p metgrid || exit 1

eos
    links=env.run.preprocessor_links.send(env.run.metgrid_select)
    f=File.join('$NUWRFDIR','WPS','metgrid',links[0])
    l=File.join('metgrid',links[1])
    script<<"ln -fs #{f} #{l} || exit 1\n"

    check=<<-eos
if [ ! -e metgrid/#{links[1]} ] ; then 
    echo "ERROR, metgrid/#{links[1]} does not exist!"
    exit 1
fi
eos
    script+check
  end

  ##############################################################################
  def createMetgridPreprocessorScript(env)

    header=createPreprocessorHeader(env,'metgrid')

    body=createCommonPreprocessorBody(env,'metgrid','namelist.wps')

    body<<createMetgridLinks(env)

    footer=<<-eos
# Run metgrid.exe
ln -fs $NUWRFDIR/WPS/metgrid/src/metgrid.exe metgrid.exe || exit 1
if [ ! -e "metgrid.exe" ] ; then
    echo "ERROR, metgrid.exe does not exist!"
    exit 1
fi
mpirun -np $SLURM_NTASKS ./metgrid.exe || exit 1

# Tidy up logs
mkdir -p metgrid_logs || exit 1

mv metgrid.log.* metgrid_logs

# The end
exit 0
eos

    header+body+footer
  end

  ##############################################################################
  def createRealLinks(env)

    script=""
    links=env.run.preprocessor_links.send(env.run.real_select)
    links.each do |l|
      fw=File.join('$WORKDIR',l)
      f=File.join('$NUWRFDIR','WRFV3','run',l)
      check=<<-eos
if [ ! -e #{f} ] ; then 
    echo "ERROR, #{f} does not exist!"
    exit 1
fi
eos
      script<<check
      script<<"ln -fs #{f} #{fw} || exit 1\n"
      
    end
    script
  end

  ##############################################################################
  def createRealPreprocessorScript(env)

    header=createPreprocessorHeader(env,'real')

    body=createCommonPreprocessorBody(env,'real','namelist.input.real')

    body<<createRealLinks(env)

    footer=<<-eos

# Make real's namelist current
rm namelist.input
ln -s namelist.input.real namelist.input

# Run real.exe
ln -fs $NUWRFDIR/WRFV3/main/real.exe $WORKDIR/real.exe || exit 1
if [ ! -e $WORKDIR/real.exe ] ; then
    echo "ERROR, $WORKDIR/real.exe does not exist!"
    exit 1
fi

mpirun -np $SLURM_NTASKS ./real.exe || exit 1

#Backup Real's output files
cp namelist.output namelist.output.real

bdy_files=`ls wrfbdy_d??`
for file in $bdy_files ; do
    cp $file ${file}.real
done

input_files=`ls wrfinput_d??`
for file in $input_files ; do
    cp $file ${file}.real
done

# Rename the various 'rsl' files to 'real.rsl'; this prevents wrf.exe from
# overwriting.
rsl_files=`ls rsl.*`
for file in $rsl_files ; do
    mv $file real.${file}
done

# Tidy up logs
mkdir -p real_logs || exit 1

mv real.rsl.* real_logs

# The end
exit 0
eos

    header+body+footer
  end

  ##############################################################################
  def createGocart2wrfPreprocessorScript(env)

    header=createPreprocessorHeader(env,'gocart2wrf')

    body=createCommonPreprocessorBody(env,'gocart2wrf','namelist.gocart2wrf')

    footer=<<-eos
# Run gocart2wrf.  No MPI is used since the program is serial.
ln -fs $NUWRFDIR/utils/gocart2wrf_2/bin/gocart2wrf gocart2wrf || exit 1
if [ ! -e gocart2wrf ] ; then
    echo "ERROR, gocart2wrf not found!"
    exit 1
fi
./gocart2wrf || exit 1

#Backup Gocart2wrf's output files
cp namelist.output namelist.output.gocart2wrf

bdy_files=`ls wrfbdy_d??`
for file in $bdy_files ; do
    cp $file ${file}.gocart2wrf
done

input_files=`ls wrfinput_d??`
for file in $input_files ; do
    cp $file ${file}.gocart2wrf
done

# The end
exit 0
eos
    header+body+footer
  end

  ##############################################################################
  def createCasa2wrfLinks(env)

    script=<<-eos

if [ -e chem_flux ] ; then
    rm -rf chem_flux || exit 1
fi
mkdir -p chem_flux || exit 1

eos
    links=env.run.preprocessor_links.send(env.run.casa2wrf_select)
    links.each do |link|
      f=link[0]
      l=link[1]

      check=<<-eos
if [ ! -e #{f} ] ; then 
    echo "ERROR, #{f} does not exist!"
    exit 1
fi
eos
      script<<check
      script<<"ln -fs #{f} #{l} || exit 1\n"
    end

    script
  end

  ##############################################################################
  def createCasa2wrfPreprocessorScript(env)

    header=createPreprocessorHeader(env,'casa2wrf')

    body=createCommonPreprocessorBody(env,'casa2wrf','namelist.casa2wrf')

    body<<createCasa2wrfLinks(env)

    footer=<<-eos
# Run casa2wrf.  No MPI is used since the program is serial.
ln -fs $NUWRFDIR/utils/casa2wrf/bin/casa2wrf casa2wrf || exit 1
if [ ! -e casa2wrf ] ; then
    echo "ERROR, casa2wrf not found!"
    exit 1
fi
./casa2wrf || exit 1

#Backup casa2wrf's output files

bdy_files=`ls wrfbdy_d??`
for file in $bdy_files ; do
    cp $file ${file}.casa2wrf
done

input_files=`ls wrfinput_d??`
for file in $input_files ; do
    cp $file ${file}.casa2wrf
done


# Tidy up logs
#mkdir -p casa2wrf_logs || exit 1

#mv casa2wrf.out casa2wrf_logs

# The end
exit 0
eos

    header+body+footer
  end

  ##############################################################################
  def createPrepchemsourcesLinks(env)

    script=""
    links=env.run.preprocessor_links.send(env.run.prep_chem_sources_select)
    links.each do |link|
      f=link[0]
      l=link[1]

      check=<<-eos
if [ ! -e #{f} ] ; then 
    echo "ERROR, #{f} does not exist!"
    exit 1
fi
eos
      script<<check
      script<<"ln -fs #{f} #{l} || exit 1\n"
    end

    script
  end


  ##############################################################################
  def createPrepchemsourcesPreprocessorScript(env)

    header=createPreprocessorHeader(env,'prep_chem_sources')

    body=createCommonPreprocessorBody(env,'prep_chem_sources')

    body<<createPrepchemsourcesLinks(env)

    footer=<<-eos
# Run prep_chem_sources_RADM_WRF_FIM.exe.  No MPI is used since the program is serial.
ln -fs $NUWRFDIR/utils/prep_chem_sources/bin/prep_chem_sources_RADM_WRF_FIM.exe || exit 1
if [ ! -e prep_chem_sources_RADM_WRF_FIM.exe ] ; then
    echo "ERROR, prep_chem_sources_RADM_WRF_FIM.exe not found!"
    exit 1
fi
./prep_chem_sources_RADM_WRF_FIM.exe || exit 1

# The end
exit 0
eos

    header+body+footer
  end


  def getPreprocessorScriptName(p)
    p+'.bash' 
  end


  ##############################################################################
  def createConvertemissLinks(env)

    script=""
    links=env.run.preprocessor_links.send(env.run.convert_emiss_select)
    links.each do |l|
      fw=File.join('$WORKDIR',l)
      f=File.join('$NUWRFDIR','WRFV3','run',l)
      check=<<-eos
if [ ! -e #{f} ] ; then 
    echo "ERROR, #{f} does not exist!"
    exit 1
fi
eos
      script<<check
      script<<"ln -fs #{f} #{fw} || exit 1\n"

    end
    script
  end

  ##############################################################################
  def createConvertemissPreprocessorScript(env)

    header=createPreprocessorHeader(env,'convert_emiss')

    body=createCommonPreprocessorBody(env,'convert_emiss','namelist.input.convert_emiss.d01')

    body<<createConvertemissLinks(env)

    testphrase="EMISSIONS CONVERSION : end of program"

    footer=<<-eos

# Link convert_emiss
ln -fs $NUWRFDIR/WRFV3/chem/convert_emiss.exe $WORKDIR/convert_emiss.exe || exit 1
if [ ! -e $WORKDIR/convert_emiss.exe ] ; then
    echo "ERROR, $WORKDIR/convert_emiss.exe does not exist!"
    exit 1
fi

# logs directory
mkdir -p convert_emiss_logs || exit 1

numDomains=3

# Loop through each domain. convert_emiss only processes a single domain, so
# creative renaming is necessary to process multiple domains.
domain_total=0
domain_pass=0
for domain in `seq 1 $numDomains` ; do
        
    g=g${domain}

    if [ $domain -lt 10 ] ; then
        d=d0${domain}
    else
        d=d${domain}
    fi

    echo "Processing domain ${d}"

    # Count files, and exit for loop if no files are found for current domain.
    count=`ls -x -1 | grep -e "^wrfinput_${d}$" | wc -l`
    if [ $count -eq 0 ] ; then
        echo "No input files found for domain ${d}; skipping..."
        break
    fi

    echo "Found ${count} input files"

    if [ ! -e namelist.input.convert_emiss.${d} ] ; then
        echo "ERROR, namelist.input.convert_emiss.${d} not found!"
        exit 1
    fi

    # Make convert_emiss's namelist current
    rm namelist.input
    ln -fs namelist.input.convert_emiss.${d} namelist.input || exit 1

    if [ ! -e wrfinput_${d} ] ; then
        echo "ERROR, wrfinput_${d} does not exist!"
        exit 1
    fi

    mv wrfinput_${d} wrfinput_${d}.actual || exit 1
    ln -s wrfinput_${d}.actual wrfinput_d01 || exit 1

    # Symbolically link emissions files.
    for link in emissopt3_d01 emissfire_d01 wrf_gocart_backg ; do

        if [ $link = "emissopt3_d01" ] ; then
            abbrev="ab"
        elif [ $link = "emissfire_d01" ] ; then
            abbrev="bb"
        elif [ $link = "wrf_gocart_backg" ] ; then
            abbrev="gocartBG"
        else
            echo "Internal logic error, unknown symlink $link"
            exit 1
        fi

        # Create the symbolic link.
        # FIXME: Need better way of doing this.
        numfiles=`ls -l *${g}-${abbrev}.bin | wc -l`
        if [ $numfiles -ne 1 ] ; then
            echo $numfiles
            echo "ERROR, found multiple -${g}-${abbrev}.bin files!"
            echo "Do you really need a $link file?"
            exit 1
        fi
        targets=`ls *${g}-${abbrev}.bin`
        for target in $targets ; do
            ln -fs $target $link || exit 1
            if [ ! -e $link ] ; then
                echo "ERROR, $link does not exist!"
                exit 1
            fi
        done
    done

    # Run convert_emiss
    # WARNING: This program only supports a single process even when compiled
    # with MPI.

    mpirun -np 1 ./convert_emiss.exe || exit 1

    # Remove symbolic link
    rm wrfinput_d01 || exit 1

    # Rename the output files to prevent overwriting from different grid
    if [ -e wrfbiochemi_d01 ] ; then
        mv wrfbiochemi_d01 wrfbiochemi_${d}.actual || exit 1
    fi
    if [ -e wrfchemi_d01 ] ; then
        mv wrfchemi_d01 wrfchemi_${d}.actual || exit 1
    fi
    if [ -e wrfchemi_gocart_bg_d01 ] ; then
        mv wrfchemi_gocart_bg_d01 wrfchemi_gocart_bg_${d}.actual || exit 1
    fi
    if [ -e wrffirechemi_d01 ] ; then
        mv wrffirechemi_d01 wrffirechemi_${d}.actual || exit 1
    fi

    let "domain_total = domain_total + 1"
    test=`grep "#{testphrase}" rsl.out.0000 | wc -l`
    if [ $test -eq 1 ] ; then 
      let "domain_pass = domain_pass + 1"
    fi

    # Tidy up logs...
    # Rename the various 'rsl' files to 'convert_emiss.rsl'; this prevents 
    # other processing from overwriting.
    rsl_files=`ls rsl.*`
    for file in $rsl_files ; do
        mv $file convert_emiss.${file}.${d} || exit 1
    done
    mv convert_emiss.rsl.* convert_emiss_logs

done

#Harvest date time information from the namelist.input file
iyr=`grep start_year namelist.input | awk -F "=" '{print $2}'| awk -F "," '{print $1}' | sed 's/^[ \t]*//'`
imon=`grep start_month namelist.input | awk -F "=" '{print $2}'| awk -F "," '{print $1}' | sed 's/^[ \t]*//'`
iday=`grep start_day namelist.input | awk -F "=" '{print $2}'| awk -F "," '{print $1}' | sed 's/^[ \t]*//'`
ihr=`grep start_hour namelist.input | awk -F "=" '{print $2}'| awk -F "," '{print $1}' | sed 's/^[ \t]*//'`
imin=`grep start_minute namelist.input | awk -F "=" '{print $2}'| awk -F "," '{print $1}' | sed 's/^[ \t]*//'`
isec=`grep start_second namelist.input | awk -F "=" '{print $2}'| awk -F "," '{print $1}' | sed 's/^[ \t]*//'`

idate="${iyr}-${imon}-${iday}"
itime="${ihr}:${imin}:${isec}"

echo "namelist.input contains the following start date and time: ${idate} ${itime}"

# Restore the original file names
for domain in `seq 1 $numDomains` ; do
    if [ $domain -lt 10 ] ; then
        d=d0${domain}
    else
        d=d${domain}
    fi
    if [ -e wrfinput_${d}.actual ] ; then
        mv wrfinput_${d}.actual wrfinput_${d} || exit 1
    fi
    if [ -e wrfbiochemi_${d}.actual ] ; then
        mv wrfbiochemi_${d}.actual wrfbiochemi_${d} || exit 1
    fi
    if [ -e wrfchemi_${d}.actual ] ; then
        mv wrfchemi_${d}.actual wrfchemi_${d}_${idate}_${itime} || exit 1
    fi
    if [ -e wrfchemi_gocart_bg_${d}.actual ] ; then
        mv wrfchemi_gocart_bg_${d}.actual wrfchemi_gocart_bg_${d}_${idate} || exit 1
    fi
    if [ -e wrffirechemi_${d}.actual ] ; then
        mv wrffirechemi_${d}.actual wrffirechemi_${d}_${idate}_${itime} || exit 1
    fi
done

#Final processing check
echo "${domain_pass} out of ${domain_total} domains succeeded" > convert_emiss_results.out
if [ $domain_total -eq $domain_pass ] ; then
  echo "Success" >> convert_emiss_results.out
fi

#Tidy up log
mv convert_emiss_results.out convert_emiss_logs

# The end
echo "Done"
exit 0
eos

    header+body+footer
  end

  ##############################################################################
  def createWrfLinks(env)
    script=""
    if env.run.wrf_select and env.run.wrf_select.class == Array
      env.run.wrf_select.each do |type|
        script<<createTypedLinks(env,type)
      end      
    elsif env.run.wrf_select
      script<<createTypedLinks(env,env.run.wrf_select)
    end
    script
  end

  ##############################################################################
  def createWrfPreprocessorScript(env)

    header=createPreprocessorHeader(env,'wrf')

    body=createCommonPreprocessorBody(env,'wrf','namelist.input.wrf')

    body<<createWrfLinks(env)

    footer=<<-eos

# Make lis connections as appropriate
if [ -f lis.config.wrf ] ; then
  rm lis.config
  ln -s lis.config.wrf lis.config || exit 1
fi

# Make wrf's namelist current
rm namelist.input
ln -s namelist.input.wrf namelist.input

# Run wrf.exe
ln -fs $NUWRFDIR/WRFV3/main/wrf.exe $WORKDIR/wrf.exe || exit 1
if [ ! -e $WORKDIR/wrf.exe ] ; then
    echo "ERROR, $WORKDIR/wrf.exe does not exist!"
    exit 1
fi

mpirun -np $SLURM_NTASKS ./wrf.exe || exit 1

# Rename the various 'rsl' files to 'wrf.rsl'; this prevents real.exe from
# overwriting.
rsl_files=`ls rsl.*`
for file in $rsl_files ; do
    mv $file wrf.${file}
done

# Tidy up logs
mkdir -p wrf_logs || exit 1

mv wrf.rsl.* wrf_logs

# Tidy up logs
mkdir -p wrf_lis_logs || exit 1

mv lislog.* wrf_lis_logs

sleep 60

# The end
exit 0
eos

    header+body+footer
  end

  ##############################################################################
  def createRipLinks(env)

    script=""
    links=env.run.preprocessor_links.send(env.run.rip_select)
    links.each do |l|
      fname=l+".in"
      fw=File.join('$WORKDIR',fname)
      f=File.join('$NUWRFDIR','scripts','rip',fname)
      check=<<-eos
if [ ! -e #{f} ] ; then 
    echo "ERROR, #{f} does not exist!"
    exit 1
fi
eos
      script<<check
      script<<"ln -fs #{f} #{fw} || exit 1\n"

    end
    script
  end

  ##############################################################################
  def listRipNames(env)
    list=""
    links=env.run.preprocessor_links.send(env.run.rip_select)
    links.each do |l|
      list<<l+" "
    end
    list
  end

  ##############################################################################
  def createRipPreprocessorScript(env)

    header=createPreprocessorHeader(env,'rip')

    body=createCommonPreprocessorBody(env,'rip')

    body<<createRipLinks(env)

    body<<"ripfiles=\"#{listRipNames(env)}\"\n"

    testphrase="We're outta here like Vladimir"

    footer=<<-eos

# Link rip and rip preprocessor to work directory.
if [ -z "$RIP_ROOT" ] ; then
    echo "ERROR, RIP_ROOT is not defined!"
    exit 1
fi
ln -fs $RIP_ROOT/ripdp_wrfarw ripdp_wrfarw || exit 1
if [ ! -e ripdp_wrfarw ] ; then
    echo "ERROR, ripdp_wrfarw does not exist!"
    exit 1
fi
ln -fs $RIP_ROOT/rip rip || exit 1
if [ ! -e rip ] ; then
    echo "ERROR, rip does not exist!"
    exit 1
fi

# Process each domain
domain_total=0
domain_pass=0
for domain in d01 d02 d03 d04 ; do

    # Count files, and exit for look if no files are found for current domain.
    count=`ls -x -1 | grep wrfout_${domain} | wc -l`

    if [ $count -eq 0 ] ; then
        break
    fi

    let "domain_total = domain_total + 1"

    # Run preprocessor on current domain wrfout files
    files=`ls wrfout_${domain}_*_00:* wrfout_${domain}_*_03:* \
              wrfout_${domain}_*_06:* wrfout_${domain}_*_09:* \
              wrfout_${domain}_*_12:* wrfout_${domain}_*_15:* \
              wrfout_${domain}_*_18:* wrfout_${domain}_*_21:*`
    ./ripdp_wrfarw nuwrf_${domain} all $files || exit 1

    # Now run rip for each rip-execution-name.  Rename the cgm file to
    # prevent overwrites when processing a different domain.
    total=0
    pass=0
    for ripfile in $ripfiles ; do
        ./rip -f nuwrf_${domain} $ripfile || exit 1
        mv ${ripfile}.cgm ${ripfile}_${domain}.cgm || exit 1
        mv ${ripfile}.out ${ripfile}_${domain}.out || exit 1
        test=`grep "#{testphrase}" ${ripfile}_${domain}.out | wc -l`
        let "total = total + 1"
        if [ $test -eq 1 ] ; then
          let "pass = pass + 1"
        fi
    done
    if [ $total -eq $pass ] ; then
      let "domain_pass = domain_pass + 1"
    fi
    echo "${pass} out of ${total} rip charts succeeded for ${domain} domain" > rip_result_${domain}.out
    rm -fv nuwrf_${domain}_*.00000_* 
done

echo "${domain_pass} out of ${domain_total} domains succeeded" > rip_results.out
if [ $domain_total -eq $domain_pass ] ; then
  echo "Success" >> rip_results.out
fi

# Tidy up logs
mkdir -p rip_logs || exit 1

mv rip_result* rip_logs

# The end
exit 0
eos

    header+body+footer
  end

  ##############################################################################
  def createGsdsuLinks(env)

    script=""
    links=env.run.preprocessor_links.send(env.run.gsdsu_select)
    links.each do |l|
      fname=l
      fw=File.join('$WORKDIR',fname)
      f=File.join('$NUWRFDIR','GSDSU',fname)
      check=<<-eos
if [ ! -e #{f} ] ; then 
    echo "ERROR, #{f} does not exist!"
    exit 1
fi
eos
      script<<check
      script<<"ln -fs #{f} #{fw} || exit 1\n"

    end
    script
  end

  ##############################################################################
  def createGsdsuPreprocessorScript(env)
  
    header=createPreprocessorHeader(env,'gsdsu')
    
    body=createCommonPreprocessorBody(env,'gsdsu','Configure_SDSU.F')

    body<<createGsdsuLinks(env)

    footer=<<-eos
#create the output directory
mkdir -p $WORKDIR/OUTPUTS || exit 1

# Run GSDSU.x
ln -fs $NUWRFDIR/GSDSU/QRUN/GSDSU.x $WORKDIR/GSDSU.x || exit 1
if [ ! -e $WORKDIR/GSDSU.x ] ; then 
    echo "ERROR, GSDSU.x does not exist!"
    exit 1
fi
mpirun -np $SLURM_NTASKS ./GSDSU.x || exit 1

# The end
exit 0
eos

    header+body+footer
  end

  ##############################################################################
  def run_local_job(env,rundir,preprocessor)
    jobid=nil
    re1=Regexp.new(lib_re_str_job_id)
    ss=File.join(".",getPreprocessorScriptName(preprocessor))
    cmd="cd #{rundir} && #{ss}"
    logd "Executing job with command: #{cmd}"
    output,status=ext(cmd,{:msg=>"Job execution failed"})
    output.each do |e|
      e.chomp!
      logd e
    end
    outfile=File.join(rundir,env.run.expectedStatusFiles.send(preprocessor)[0])
    if File.exists?(outfile)
      logd "#{outfile} found"
    else
      logd "ERROR: #{outfile} not found"
    end
    outfile
  end

  ##############################################################################
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

  ##############################################################################
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
 
  ##############################################################################
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

puts "Loaded userutil.rb" 

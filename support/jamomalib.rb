###################################################################
# Library of Ruby stuff for Jamoma
###################################################################

require 'yaml'
$g_use_yaml_project_files = true
@debug = false

require 'rexml/document'
require 'rexml/formatters/pretty'
include REXML


if defined? win32?
else
  
  require 'open3'
  require 'fileutils'
  require 'pathname'
  if defined? $main_repository
    require "#{Dir.pwd}/buildTools/platform"
  else
    require "#{Dir.pwd}/platform"
  end
  require 'rexml/document'
  include REXML

  def win32?
    (Platform::OS == :unix && Platform::IMPL == :cygwin) || Platform::OS == :win32
  end

  def linux?
    (Platform::IMPL == :linux)
  end

  if linux?
    def beagle?
      return true if `arch`.match("armv7l")
      return false
    end
  else
    def beagle?
      return false
    end
  end

if win32?
  if defined? $main_repository
    if Platform::IMPL == :cygwin
      require "#{Dir.pwd}/support/wininit"
    else
      require "#{Dir.pwd}/support/wininit.rb"
    end
  else
    if Platform::IMPL == :cygwin
      require "#{Dir.pwd}/wininit"
    else
      require "#{Dir.pwd}/wininit.rb"
    end
  end
end

if win32?
  def mac?
    false
  end
elsif linux?
  def mac?
    false
  end
else
  def mac?
    true
  end
end

  #######
  ## SUB ROUTINES
  #######

  if (defined? quietly) == nil
    def quietly
      v = $VERBOSE
      $VERBOSE = nil
      yield
      ensure
      $VERBOSE = v
    end
  end

  def create_logs(str)
    # set up log files and ensure that the build_root is there
    `mkdir -p #{@log_root}` if !FileTest.exist?(@log_root)
    @build_log = File.new("#{@log_root}/build.log", "w")
    @build_log.write("#{str.upcase} BUILD LOG: #{`date`}\n\n")
    @build_log.flush
    @error_log = File.new("#{@log_root}/error.log", "w")
    @error_log.write("#{str.upcase} BUILD ERROR LOG:\n")
    @error_log.write("           STARTED:   #{`date`}")
    @error_log.flush
    trap("SIGINT") { die }
  end
 
  def create_test_logs
    # set up log files and ensure that the build_root is there
    `mkdir -p #{@log_root}` if !FileTest.exist?(@log_root)
    @testPass_log = File.new("#{@log_root}/pass.log", "w")
    @testPass_log.write("JAMOMA TEST PASS LOG: #{`date`}\n\n")    
    @testFail_log = File.new("#{@log_root}/fail.log", "w")
    @testFail_log.write("JAMOMA TEST FAIL LOG:\n")
    @testFail_log.write("           STARTED:   #{`date`}")
    @testFail_log.flush
    trap("SIGINT") { 
      puts "Crash!"
      @testFail_log.close
    }    
  end
  
  def die
    close_logs
    exit 0
  end

  def close_logs
    @error_log.write("           COMPLETED: #{`date`}")
    #@error_log.write("="*45)
    @error_log.close
    @build_log.write("           COMPLETED: #{`date`}")
    @build_log.close
   
  end
  
  def close_test_logs
    @testPass_log.write("COMPLETED: #{`date`}")
    @testPass_log.close    
    @testFail_log.write("           COMPLETED: #{`date`}")
    @testFail_log.close
  end

  def log_build(str)
    @build_log.write(str)
    @build_log.write("\n\n")
    @build_log.flush
  end

  def log_error(str)
    if (str.length > 0)     
      @error_log.write(str)
      @error_log.write("\n\n")
      @error_log.flush
    end
  end
  
  def log_test_fail(str)
    @testFail_log.write(str)
    @testFail_log.write("\n")
    @testFail_log.flush
  end
  
  def log_test_pass(str)
    @testPass_log.write(str)
    @testPass_log.write("\n")
    @testPass_log.flush
  end
  

  def zero_count
    @cur_total = 0
    @cur_count = 0
  end

  def get_count
    return @cur_total, @cur_count
  end


  def copydir(sourcepath, dstpath)
    out = ""
    err = ""
    inputstr = "#{sourcepath}".ljust(80)
    puts "copy -v #{inputstr} --> #{dstpath}"    
    Open3.popen3("rm -rf #{dstpath}") do |stdin, stdout, stderr|
      out = stdout.read
      err = stderr.read
    end
    log_build(out)
    log_error(err)

    Open3.popen3("cp -R #{sourcepath} #{dstpath}") do |stdin, stdout, stderr|
      out = stdout.read
      err = stderr.read
    end
    log_build(out)
    log_error(err)

    return 0  
  end


  def copyfile(filename, sourcepath, dstpath)
    out = ""
    err = ""
    # enable the next two lines if yo want to see the verbose infos  
    #inputstr = "#{sourcepath}/#{filename}".ljust(80)
    #puts "cp -R #{inputstr} --> #{dstpath}/#{filename}"
    Open3.popen3("cp -R #{sourcepath}/#{filename} #{dstpath}/#{filename}") do |stdin, stdout, stderr|
      out = stdout.read
      err = stderr.read
    end
    log_build(out)
    log_error(err)

    return 0  
  end
  
  
  def copyfile_adapt_name_to_win(filename, sourcepath, dstpath)
	out = ""
    err = ""
	
	filename_adapted = filename.gsub("≈","=")
	  inputstr = "#{sourcepath}/#{filename}".ljust(80)
    puts "copy -r  #{inputstr} --> #{dstpath}/#{filename_adapted}"

    Open3.popen3("cp -R #{sourcepath}/#{filename} #{dstpath}/#{filename_adapted}") do |stdin, stdout, stderr|
      out = stdout.read
      err = stderr.read
    end
    log_build(out)
    log_error(err)

    return 0  
  end


  def build_xcode_project(projectdir, projectname, configuration, clean, distropath)
    out = ""
    err = ""
   
    if (distropath)
      xcode_env_vars = " INSTALL_PATH=\"#{distropath}\" "
    else
      xcode_env_vars = ""
    end

    str = "nice xcodebuild -project #{projectname} -configuration #{configuration} #{xcode_env_vars} #{"clean" if clean == true} build"
    Open3.popen3(str) do |stdin, stdout, stderr|
      if(@debug)
        puts str
      end
      out = stdout.read
      err = stderr.read
    end    
    if /BUILD SUCCEEDED/.match(out)
      @cur_count+=1
      projectname = "#{projectname}".ljust(27)
      puts "#{projectname} BUILD SUCCEEDED"
      log_build(out)
      return 1
    else
      projectname = "#{projectname} ".ljust(27, '*')
      @fail_array.push("#{projectdir}/#{projectname}")
      puts "#{projectname} BUILD FAILED **************************************"
      log_error(out)
      log_error(err)
    end
    return 0
  end

  def build_make_project(projectdir, makefilename, configuration, clean)
    out = ""
    projectname = projectdir.split("/").last
    printedprojname = "#{projectname} ".ljust(27, '.')
    print "#{printedprojname} "
    STDOUT.flush

    sleep 1
    
    `make -j 4 clean 2>&1` if clean

    configuration = "Debug" if configuration == "Development"
    configuration = "Release" if configuration == "Deployment"
    out = `make -j 4 #{configuration} 2>&1`
    # if error is not followed by a colon then the clang-compiled build will claim to fail when there are no real errors  
    if /error:/.match(out) || /Error: /.match(out) || /make: \*\*\* No rule to make target/.match(out) || /No such file or directory/.match(out)
      @fail_array.push("#{projectname}")
      puts "BUILD FAILED **************************************"
      log_error(out)
    else
      @cur_count+=1      
      puts "BUILD SUCCEEDED"
      log_build(out)
      return 1
    end
    return 0

  end

  def build_vs_project(projectdir, projectname, configuration, clean)
    out = ""
    err = ""

    Open3.popen3("nice vcbuild.exe #{"/rebuild" if clean == true} \"#{projectname}\" \"#{configuration}\"") do |stdin, stdout, stderr|
      out = stdout.read
      err = stderr.read
    end
    
    if /(0 error|up\-to\-date|0 erreur)/.match(out)
      @cur_count+=1
      projectname = "#{projectname}".ljust(27)
      puts "#{projectname} BUILD SUCCEEDED"
      log_build(out)
      return 1
    else
      @fail_array.push("#{projectdir}/#{projectname}")
      projectname = "#{projectname} ".ljust(27, '*')
      puts "#{projectname} BUILD FAILED **************************************"
      log_error(out)
      log_error(err)
    end
    return 0
  end


  def build_project(projectdir, projectname, configuration, clean, distropath, use_make=false)
    if FileTest.exist?("#{projectdir}/#{projectname}") || ( use_make && FileTest.exist?("#{projectdir}/Makefile"))
      @cur_total+=1
      olddir = Dir.getwd
      Dir.chdir(projectdir)
    
      if use_make
      	@cur_count += build_make_project(projectdir, projectname, configuration, clean)
      elsif win32?
        @cur_count += build_vs_project(projectdir, projectname, configuration, clean)
      elsif linux?
	      @cur_count += build_make_project(projectdir, projectname, configuration, clean)
      else
        @cur_count += build_xcode_project(projectdir, projectname, configuration, clean, distropath)
      end

      Dir.chdir(olddir)
    else
      puts"File Does not exist: #{projectdir}/#{projectname}"
    end
  end     
  

  def copy_helpfile(filename, filedir, dstdir)
    if FileTest.exist?("#{filedir}/#{filename}")
      @cur_total+=1
      if win32?
        @cur_count += copyfile_adapt_name_to_win(filename, filedir, dstdir)
      else
        @cur_count += copyfile(filename , filedir, dstdir)       
      end
    else
      puts"File Does not exist: #{filedir}/#{filename}"
    end
  end
  
  
  # CREATE COPIES OF THE STANDARD C/C++ LIBRARIES THAT WE CAN USE FOR LINKING AND REDISTRIBUTION
  # distropath is the same as in other places in this script: it defines where the mac expects to see the lib at runtime
  # if the file is not found, then it will be searched for in /usr/local/lib
  # distropath should look something like "@executable_path/../Jamoma"
  
  # NOTE -- THIS IS CURRENTLY UNUSED BUT LEFT-IN FOR REFERENCE
  
  $already_configured_gcc47 = false
  
  def configure_gcc47(path_to_moduleroot, distropath)
    return if ($already_configured_gcc47)
    
    puts "Configuring Redistributable Libs for GCC 4.7"
    
    # First, look and see if we have already copied these in the past
    if (File.exists?("/usr/local/jamoma/lib/libgcc_s.1.dylib") && File.exists?("/usr/local/jamoma/lib/libstdc++.6.dylib"))
      # do nothing
    else
      `cp "#{path_to_moduleroot}/Shared/gcc47/libgcc_s.1.dylib"  "/usr/local/jamoma/lib/libgcc_s.1.dylib" `
      `cp "#{path_to_moduleroot}/Shared/gcc47/libstdc++.6.dylib" "/usr/local/jamoma/lib/libstdc++.6.dylib"`
      `sudo ln -s /usr/local/jamoma/lib/libgcc_s.1.dylib  /usr/local/lib/libgcc_s.1.dylib `
      `sudo ln -s /usr/local/jamoma/lib/libstdc++.6.dylib /usr/local/lib/libstdc++.6.dylib`
    end
    
    # Now that we have the libs to which we want to link, we need to write their install location into them
    `install_name_tool -id "#{distropath}/lib/libgcc_s.1.dylib"  "/usr/local/jamoma/lib/libgcc_s.1.dylib" `
    `install_name_tool -id "#{distropath}/lib/libstdc++.6.dylib" "/usr/local/jamoma/lib/libstdc++.6.dylib"`
    
    $already_configured_gcc47 = true
  end
  
  
  # CREATE A MAKEFILE FROM A YAML PROJECT DEFINITION
  
  def generate_makefile(projectdir, projectname, forcedCompiler=NIL, path_to_moduleroot="../..", distropath=NIL)
    makefile_generated = false
    distropath = "@executable_path/../Jamoma" if !distropath
    foldername = projectdir.split("/").last
    project_type = "extension"
    project_type = "library" if foldername == "library"
    
    path_to_moduleroot_win = path_to_moduleroot.gsub(/(\/)/,'\\')
    
    if ($g_use_yaml_project_files && File.exists?("#{projectdir}/#{projectname}.yml"))
      yaml = YAML.load_file( "#{projectdir}/#{projectname}.yml")
      projectname.gsub!('#','\##')     # in case there is a # in the project name, which would be interpreted as a comment symbol
      sources = yaml["sources"]
      includes = yaml["includes"]
      libraries = yaml["libraries"]
      defines = yaml["defines"]
      frameworks = nil
      frameworks = yaml["frameworks"] if mac?
      compiler = yaml["compiler"]
      compiler = forcedCompiler if forcedCompiler # manual overwriting the compiler setting from the YML file
      puts("   forced compiler is: #{compiler}") if forcedCompiler
      arch = yaml["arch"]
      prefix = yaml["prefix"]
      postbuilds = yaml["postbuilds"]
      builddir = yaml["builddir"]
      builddir = "../Builds" if !builddir

      skipIcc = false
      skipGcc47 = false
      skipGcc46 = false
      skipClang = false
      icc   = false
      gcc47 = false
      gcc46 = false
      clang = false
      gcc42 = false
      if compiler == "icc"
        skipIcc = false
        skipGcc46 = true		
        skipGcc47 = true
        skipClang = true
      elsif compiler == "gcc47"
        skipIcc = true
        skipGcc46 = true
        skipGcc47 = false
        skipClang = true
      elsif compiler == "gcc46"
        skipIcc = true
        skipGcc46 = false
        skipGcc47 = true
        skipClang = true
      elsif compiler == "gcc"
        skipIcc = true
        skipGcc46 = true        
        skipGcc47 = true
        skipClang = true
      elsif compiler == "clang"
        skipIcc = true
        skipGcc46 = true		
        skipGcc47 = true
        skipClang = false
      end

      
      # TODO: we also will want a STATIC option for e.g. iOS builds
      if win32?
        vcproj_root = Element.new "VisualStudioProject"
        vcproj_root.attributes["ProjectType"]             = "Visual C++"
      	vcproj_root.attributes["Version"]                 = "9.00"
      	vcproj_root.attributes["Name"]                    = "#{projectname}"
      	vcproj_root.attributes["ProjectGUID"]             ="{C73B580F-BC81-490A-A54C-C851BF03BE3C}"
      	vcproj_root.attributes["RootNamespace"]           ="JamomaExtension"
      	vcproj_root.attributes["Keyword"]                 = "Win32Proj"
      	vcproj_root.attributes["TargetFrameworkVersion"]  = "131072"
    	
        vcproj = Document.new
        vcproj.add_element(vcproj_root)
      
        vcproj_platwin32 = Element.new "Platform"
        vcproj_platwin32.attributes["Name"] = "Win32"
        vcproj_platforms = Element.new "Platforms"
        vcproj_platforms.add_element(vcproj_platwin32)
        vcproj_root.add_element(vcproj_platforms)
      
        vcproj_debug = Element.new "Configuration"
      	vcproj_debug.attributes["Name"]                   = "Debug|Win32"
      	vcproj_debug.attributes["OutputDirectory"]        = "..\\builds\\"
      	vcproj_debug.attributes["IntermediateDirectory"]  = "Debug"
      	vcproj_debug.attributes["ConfigurationType"]      = "2"
      
        vcproj_release = Element.new "Configuration"
      	vcproj_release.attributes["Name"]                   = "Release|Win32"
      	vcproj_release.attributes["OutputDirectory"]        = "..\\builds\\"
      	vcproj_release.attributes["IntermediateDirectory"]  = "Release"
      	vcproj_release.attributes["ConfigurationType"]      = "2"
    	
      	# Run the Script:
      	# IF NOT EXIST "$(CommonProgramFiles)\Jamoma\Extensions" mkdir "$(CommonProgramFiles)\Jamoma\Extensions"
  		  # copy $(OutDir)\$(TargetFileName) "$(CommonProgramFiles)\Jamoma\Extensions"
  		  # copy $(OutDir)\$(TargetFileName) "$(ProjectDir)..\..\..\..\Builds"
    	
      	vcproj_tool = Element.new "Tool"
      	vcproj_tool.attributes["Name"] = "VCCustomBuildTool"
      	vcproj_tool.attributes["CommandLine"] = "IF NOT EXIST \"$(CommonProgramFiles)\\Jamoma\\Extensions\" mkdir \"$(CommonProgramFiles)\\Jamoma\\Extensions\"\r\ncopy $(OutDir)\\$(TargetFileName) \"$(CommonProgramFiles)\\Jamoma\\Extensions\"\r\ncopy $(OutDir)\\$(TargetFileName) \"$(ProjectDir)..\\..\\..\\..\\Builds\"\r\n"
      	vcproj_tool.attributes["Outputs"] = "foo"
     	  vcproj_debug.add_element(vcproj_tool)
   	  
     	  # Even though the Tool definition is identical, it seems like adding it as an element to the debug element "eats" the element
     	  # So we need to make a new copy from scratch...
      	vcproj_tool = Element.new "Tool"
      	vcproj_tool.attributes["Name"] = "VCCustomBuildTool"
      	vcproj_tool.attributes["CommandLine"] = "IF NOT EXIST \"$(CommonProgramFiles)\\Jamoma\\Extensions\" mkdir \"$(CommonProgramFiles)\\Jamoma\\Extensions\"\r\ncopy $(OutDir)\\$(TargetFileName) \"$(CommonProgramFiles)\\Jamoma\\Extensions\"\r\ncopy $(OutDir)\\$(TargetFileName) \"$(ProjectDir)..\\..\\..\\..\\Builds\"\r\n"
      	vcproj_tool.attributes["Outputs"] = "foo"
  		  vcproj_release.add_element(vcproj_tool)
      else
        makefile = File.new("#{projectdir}/Makefile", "w")
        makefile.write("# Jamoma Makefile, generated by the Jamoma build system for the platform on which the build was run.\n")
        makefile.write("# Edits to this file are NOT under version control and will be lost when the build system is run again.\n")
        makefile.write("\n")
        makefile.write("NAME = #{projectname}\n\n")
        if mac?
          if ((File.exists? "/usr/bin/icc") && (skipIcc == false))
            makefile.write("CC_32 = icc -arch i386\n")
            makefile.write("CC_64 = icc -arch x86_64\n\n")
            icc = true
          elsif ((File.exists? "/usr/bin/clang++") && (skipClang == false))
            makefile.write("CC_32 = /usr/bin/clang++ -arch i386\n")
            makefile.write("CC_64 = /usr/bin/clang++ -arch x86_64\n\n")
            clang = true
          elsif ((File.exists? "/opt/local/bin/g++-mp-4.7") && (skipGcc47 == false))
            makefile.write("CC_32 = /opt/local/bin/g++-mp-4.7 -arch i386\n")
            makefile.write("CC_64 = /opt/local/bin/g++-mp-4.7 -arch x86_64\n\n")
            gcc47 = true
          else
            puts "you don't have a support compiler.  it probably isn't going to work out for the two of us..."
            clang = true
          end
          #makefile.write("CC_32 = llvm-g++-4.2 -arch i386\n")
          #makefile.write("CC_64 = llvm-g++-4.2 -arch x86_64\n\n")
        else
          makefile.write("CC = g++\n\n")
        end
  
        makefile.write("#########################################\n\n")
        i=0
        sources.each do |source|
          if mac?
           	source = source.to_s
  	       	next if source =~ /win /
          	source.gsub!(/mac /, '')
          elsif win32?
          	# This code is never executed!
           	source = source.to_s           	
  	       	next if source =~ /mac /
          	source.gsub!(/win /, '')
          else # linux?
           	source = source.to_s
  	       	next if source =~ /mac /
  	       	next if source =~ /win /
          end
          
          source32 = nil
          source64 = nil
          if mac?
            if (source.match(/\.mm/))     # objective-c code
              source32 = source.gsub(/\.mm/, ".i386.mm.o ")
              source64 = source.gsub(/\.mm/, ".x64.mm.o ") if (!arch || arch != 'i386')
            else                          # c++ code
              source32 = source.gsub(/\.cpp/, ".i386.o ")
              source64 = source.gsub(/\.cpp/, ".x64.o") if (!arch || arch != 'i386')
            end            
          else
            source.gsub!(/\.cpp/, ".o")
          end
          if (i==0)
            makefile.write("SRC32 = #{source32}\n") if source32
            makefile.write("SRC64 = #{source64}\n") if source64
            makefile.write("SRC   = #{source}\n") if !source32 && !source64
          else
            makefile.write("SRC32 += #{source32}\n") if source32
            makefile.write("SRC64 += #{source64}\n") if source64
            makefile.write("SRC   += #{source}\n") if !source32 && !source64
          end
          i+=1
        end
        makefile.write("\n\n")      
      end
  
      if win32?
        vcproj_files = Element.new "Files"
        sources.each do |source|
          source = source.to_s           	
  	      next if source =~ /mac /
          source.gsub!(/win /, '')
        	
          source_formatted_for_windows = source
          source_formatted_for_windows.gsub!(/(\/)/,'\\')
          vcproj_file = Element.new "File"
          vcproj_file.attributes["RelativePath"] = "#{source_formatted_for_windows}"
          vcproj_files.add_element(vcproj_file)
        end
      else
        makefile.write("#########################################\n\n")
        i=0
        includes.each do |include_file|
          if mac?
            next if include_file =~ /win /
            include_file.gsub!(/mac /, '')
          elsif win32?
            next if include_file =~ /mac /
            include_file.gsub!(/win /, '')
          end
          
          if (include_file == "C74-INCLUDES")
            include_file = "#{path_to_moduleroot}/../../Core/Shared/max/c74support/max-includes -I#{path_to_moduleroot}/../../Core/Shared/max/c74support/msp-includes -I#{path_to_moduleroot}/../../Core/Shared/max/c74support/jit-includes"     
          end
          
          if (i==0)
            makefile.write("INCLUDES = -I#{include_file}\n")
          else
            makefile.write("INCLUDES += -I#{include_file}\n")
          end
          i+=1
        end
        makefile.write("INCLUDE_FILES := $(wildcard INCLUDES/*.h)")
        makefile.write("\n\n")
      end

      if win32?
        concatenated_includes = ""
        includes.each do |include_file|
          concatenated_includes += "\"$(ProjectDir)#{include_file}\";"
        end
        concatenated_includes.gsub!(/(\/)/,'\\')

		concatenated_defines = ""
		if defines
		  defines.each do |define|
			concatenated_defines += ";" if concatenated_defines != ""
			concatenated_defines += "#{define}"
		  end
		end
	
       	vcproj_tool = Element.new "Tool"
       	vcproj_tool.attributes["Name"] = "VCCLCompilerTool"
       	vcproj_tool.attributes["Optimization"] = "0"
        vcproj_tool.attributes["AdditionalIncludeDirectories"] = "#{concatenated_includes}"
       	vcproj_tool.attributes["PreprocessorDefinitions"] = "WIN32;_DEBUG;_WINDOWS;_USRDLL;_CRT_SECURE_NO_WARNINGS;TT_PLATFORM_WIN;WIN_VERSION;_CRT_NOFORCE_MANIFEST;_STL_NOFORCE_MANIFEST" + ";#{concatenated_defines}"
       	vcproj_tool.attributes["MinimalRebuild"] = "true"
       	vcproj_tool.attributes["BasicRuntimeChecks"] = "3"
       	vcproj_tool.attributes["RuntimeLibrary"] = "1"
       	vcproj_tool.attributes["StructMemberAlignment"] = "2"
       	vcproj_tool.attributes["UsePrecompiledHeader"] = "0"
       	vcproj_tool.attributes["WarningLevel"] = "3"
       	vcproj_tool.attributes["Detect64BitPortabilityProblems"] = "false"
       	vcproj_tool.attributes["DebugInformationFormat"] = "4"
      	vcproj_debug.add_element(vcproj_tool)

       	vcproj_tool = Element.new "Tool"
       	vcproj_tool.attributes["Name"] = "VCCLCompilerTool"
       	vcproj_tool.attributes["Optimization"] = "3"
        vcproj_tool.attributes["AdditionalIncludeDirectories"] = "#{concatenated_includes}"
      	vcproj_tool.attributes["PreprocessorDefinitions"] = "WIN32;_DEBUG;_WINDOWS;_USRDLL;_CRT_SECURE_NO_WARNINGS;TT_PLATFORM_WIN;WIN_VERSION;_CRT_NOFORCE_MANIFEST;_STL_NOFORCE_MANIFEST" + ";#{concatenated_defines}"
      	vcproj_tool.attributes["MinimalRebuild"] = "true"
      	vcproj_tool.attributes["BasicRuntimeChecks"] = "3"
      	vcproj_tool.attributes["RuntimeLibrary"] = "1"
      	vcproj_tool.attributes["StructMemberAlignment"] = "2"
      	vcproj_tool.attributes["UsePrecompiledHeader"] = "0"
      	vcproj_tool.attributes["WarningLevel"] = "3"
      	vcproj_tool.attributes["Detect64BitPortabilityProblems"] = "false"
      	vcproj_tool.attributes["DebugInformationFormat"] = "4"
    	  vcproj_release.add_element(vcproj_tool)
      else
   
        makefile.write("#########################################\n\n")
        i=0
        
        if !libraries
          # makefile.write("LIBS = ''")
        else
          libraries.each do |lib|
            if mac?
           	lib = lib.to_s
  	       	next if lib =~ /win /
          	lib.gsub!(/mac /, '')
              if (i==0)
                makefile.write("LIBS = ")
              else
                makefile.write("LIBS += ")
              end

              if (lib == "FOUNDATION")
                makefile.write("#{path_to_moduleroot}/support/jamoma/lib/JamomaFoundation.dylib")
              elsif (lib == "MODULAR")
                makefile.write("#{path_to_moduleroot}/support/jamoma/lib/JamomaModular.dylib")
              else
                makefile.write(lib)
              end
          
            elsif linux?
           	lib = lib.to_s
  	       	next if lib =~ /mac /
  	       	next if lib =~ /win /
          	lib.gsub!(/linux /, '')
          
              if (lib == "FOUNDATION")
                if (i == 0)
                  makefile.write("LIBS = -lJamomaFoundation\n")
                  makefile.write("LIB_INCLUDES = -L#{path_to_moduleroot}/support/jamoma/lib\n")
                else
                  makefile.write("LIBS += -lJamomaFoundation\n")
                  makefile.write("LIB_INCLUDES += -L#{path_to_moduleroot}/support/jamoma/lib\n")
                end
              elsif (lib == "MODULAR")
                if (i == 0)
                  makefile.write("LIBS = -lJamomaModular\n")
                  makefile.write("LIB_INCLUDES = -L#{path_to_moduleroot}/support/jamoma/lib\n")
                else
                  makefile.write("LIBS += -lJamomaDSP\n")
                  makefile.write("LIB_INCLUDES += -L#{path_to_moduleroot}/support/jamoma/lib\n")
                end              
             else
                lib_dir = lib.split "/"
                if (i == 0)
                  makefile.write("LIBS = -l#{lib}\n")
                  makefile.write("LIB_INCLUDES = -L#{lib_dir}\n")
                else
                  makefile.write("LIBS += -l#{lib}\n")
                  makefile.write("LIB_INCLUDES += -L#{lib_dir}\n")
                end
              end
            end
        
            makefile.write("\n")
            i+=1
          end
        end
        makefile.write("\n\n")
      end
  
      if frameworks
        frameworks.each do |framework|
          if i == 0
            makefile.write("LIBS = /System/Library/Frameworks/#{framework}.framework/Versions/A/#{framework}\n")
          else
            makefile.write("LIBS += /System/Library/Frameworks/#{framework}.framework/Versions/A/#{framework}\n")
          end
          i+=1
        end
        makefile.write("\n\n")
      end
   
      if win32?
    
        concatenated_libs_debug = ""
        concatenated_lib_dirs_debug = ""
        concatenated_libs_release = ""
        concatenated_lib_dirs_release = ""
        
        libraries.each do |lib|
        	lib = lib.to_s
         	next if lib =~ /mac /
        	lib.gsub!(/win /, '')
        	
        	next if lib =~/RELEASE /
	       	lib.gsub!(/DEBUG /, '')     	

          if (lib == "FOUNDATION")
            concatenated_libs_debug += "JamomaFoundation.lib "
            concatenated_lib_dirs_debug += "\"$(ProjectDir)#{path_to_moduleroot_win}\\..\\..\\Core\\Foundation\\library\\$(ConfigurationName)\";"
          elsif (lib == "DSP")
            concatenated_libs_debug += "JamomaDSP.lib "
            concatenated_lib_dirs_debug += "\"$(ProjectDir)#{path_to_moduleroot_win}\\..\\..\\Core\\DSP\\library\\$(ConfigurationName)\";"
          elsif (lib == "MODULAR")
            concatenated_libs_debug += "JamomaModular.lib "
            concatenated_lib_dirs_debug += "\"$(ProjectDir)#{path_to_moduleroot_win}\\..\\..\\Modules\\Modular\\library\\$(ConfigurationName)\";"            
          elsif (lib == "GRAPH")
            concatenated_libs_debug += "JamomaGraph.lib "
            concatenated_lib_dirs_debug += "\"$(ProjectDir)#{path_to_moduleroot_win}\\..\\..\\Core\\Graph\\library\\$(ConfigurationName)\";"
          elsif (lib == "AUDIOGRAPH")
            concatenated_libs_debug += "JamomaAudioGraph.lib "
            concatenated_lib_dirs_debug += "\"$(ProjectDir)#{path_to_moduleroot_win}\\..\\..\\Core\\AudioGraph\\library\\$(ConfigurationName)\";"
          elsif (lib == "C74-MAX")
            concatenated_libs_debug += "MaxAPI.lib "
            concatenated_lib_dirs_debug += "\"$(ProjectDir)#{path_to_moduleroot_win}\\..\\..\\Core\\Shared\\max\\c74support\\max-includes\";"
          elsif (lib == "C74-MSP")
            concatenated_libs_debug += "MaxAudio.lib "
            concatenated_lib_dirs_debug += "\"$(ProjectDir)#{path_to_moduleroot_win}\\..\\..\\Core\\Shared\\max\\c74support\\msp-includes\";"
          elsif (lib == "C74-JITTER")
            concatenated_libs_debug += "jitlib.lib "
            concatenated_lib_dirs_debug += "\"$(ProjectDir)#{path_to_moduleroot_win}\\..\\..\\Core\\Shared\\max\\c74support\\jit-includes\";"            
          else
            lib_dir = lib.split "/"
            lib = lib_dir.pop
            lib_dir = lib_dir.join "/"
             
            lib_dir.gsub!(/(\/)/,'\\')
            concatenated_libs_debug += "#{lib} "
            concatenated_lib_dirs_debug += "\"#{lib_dir}\";"
          end
        end
 
        libraries.each do |lib|
        	lib = lib.to_s
         	next if lib =~ /mac /
        	lib.gsub!(/win /, '')
        	
        	next if lib =~/DEBUG /
        	lib.gsub!(/RELEASE /, '')        	

          if (lib == "FOUNDATION")
            concatenated_libs_release += "JamomaFoundation.lib "
            concatenated_lib_dirs_release += "\"$(ProjectDir)#{path_to_moduleroot_win}\\..\\..\\Core\\Foundation\\library\\$(ConfigurationName)\";"
          elsif (lib == "DSP")
            concatenated_libs_release += "JamomaDSP.lib "
            concatenated_lib_dirs_release += "\"$(ProjectDir)#{path_to_moduleroot_win}\\..\\..\\Core\\DSP\\library\\$(ConfigurationName)\";"
          elsif (lib == "MODULAR")
            concatenated_libs_release += "JamomaModular.lib "
            concatenated_lib_dirs_release += "\"$(ProjectDir)#{path_to_moduleroot_win}\\..\\..\\Modules\\Modular\\library\\$(ConfigurationName)\";"            
          elsif (lib == "GRAPH")
            concatenated_libs_release += "JamomaGraph.lib "
            concatenated_lib_dirs_release += "\"$(ProjectDir)#{path_to_moduleroot_win}\\..\\..\\Core\\Graph\\library\\$(ConfigurationName)\";"
          elsif (lib == "AUDIOGRAPH")
            concatenated_libs_release += "JamomaAudioGraph.lib "
            concatenated_lib_dirs_release += "\"$(ProjectDir)#{path_to_moduleroot_win}\\..\\..\\Core\\AudioGraph\\library\\$(ConfigurationName)\";"
          elsif (lib == "GRAPHICS")
            concatenated_libs_release += "JamomaGraphics.lib "
            concatenated_lib_dirs_release += "\"$(ProjectDir)#{path_to_moduleroot_win}\\..\\..\\Core\\Graphics\\library\\$(ConfigurationName)\";"
          elsif (lib == "C74-MAX")
            concatenated_libs_debug += "MaxAPI.lib "
            concatenated_lib_dirs_debug += "\"$(ProjectDir)#{path_to_moduleroot_win}\\..\\..\\Core\\Shared\\max\\c74support\\max-includes\";"
          elsif (lib == "C74-MSP")
            concatenated_libs_debug += "MaxAudio.lib "
            concatenated_lib_dirs_debug += "\"$(ProjectDir)#{path_to_moduleroot_win}\\..\\..\\Core\\Shared\\max\\c74support\\msp-includes\";"
          elsif (lib == "C74-JITTER")
            concatenated_libs_debug += "jitlib.lib "
            concatenated_lib_dirs_debug += "\"$(ProjectDir)#{path_to_moduleroot_win}\\..\\..\\Core\\Shared\\max\\c74support\\jit-includes\";" 
          else
            lib_dir = lib.split "/"
            lib = lib_dir.pop
            lib_dir = lib_dir.join "/"
             
            lib_dir.gsub!(/(\/)/,'\\')
            concatenated_libs_release += "#{lib} "
            concatenated_lib_dirs_release += "\"#{lib_dir}\";"
          end
        end
      
       	vcproj_tool = Element.new "Tool"
       	vcproj_tool.attributes["Name"] = "VCLinkerTool"
       	vcproj_tool.attributes["AdditionalDependencies"] = "#{concatenated_libs_debug}"
        if project_type == "library"
          vcproj_tool.attributes["OutputFile"] = "$(OutDir)\$(ProjectName).dll"
        else
          vcproj_tool.attributes["OutputFile"] = "$(OutDir)\$(ProjectName).ttdll"
        end
       	vcproj_tool.attributes["LinkIncremental"] = "2"
       	vcproj_tool.attributes["AdditionalLibraryDirectories"] = "#{concatenated_lib_dirs_debug}"
       	vcproj_tool.attributes["GenerateManifest"] = "false"
       	vcproj_tool.attributes["ModuleDefinitionFile"] = ""
       	vcproj_tool.attributes["GenerateDebugInformation"] = "true"
       	vcproj_tool.attributes["SubSystem"] = "2"
       	vcproj_tool.attributes["TargetMachine"] = "1"
      	vcproj_debug.add_element(vcproj_tool)
      
       	vcproj_tool = Element.new "Tool"
       	vcproj_tool.attributes["Name"] = "VCLinkerTool"
       	vcproj_tool.attributes["AdditionalDependencies"] = "#{concatenated_libs_release}"
        if project_type == "library"
          vcproj_tool.attributes["OutputFile"] = "$(OutDir)\$(ProjectName).dll"
        else
          vcproj_tool.attributes["OutputFile"] = "$(OutDir)\$(ProjectName).ttdll"
        end
       	vcproj_tool.attributes["LinkIncremental"] = "1"
       	vcproj_tool.attributes["AdditionalLibraryDirectories"] = "#{concatenated_lib_dirs_release}"
       	vcproj_tool.attributes["GenerateManifest"] = "false"
       	vcproj_tool.attributes["ModuleDefinitionFile"] = ""
       	vcproj_tool.attributes["GenerateDebugInformation"] = "true"
       	vcproj_tool.attributes["SubSystem"] = "2"
       	vcproj_tool.attributes["TargetMachine"] = "1"
  			vcproj_tool.attributes["OptimizeReferences"] = "2"
  			vcproj_tool.attributes["EnableCOMDATFolding"] = "2"
      	vcproj_release.add_element(vcproj_tool)
      
      else   
 
        makefile.write("#########################################\n\n")
        makefile.write("OPTIMIZATION_DEBUG = -O0\n")
        makefile.write("OPTIMIZATION_RELEASE = -O3\n")
        makefile.write("\n")
        if mac?
          if icc            
            makefile.write("OPTIONS = -dynamiclib -ip -msse3 -ftz -fno-alias -fp-model fast=2\n")
            # ftz:             Flushes denormal results to zero.
            # ip :             Interprocedural Optimizations such as function inlining, dead code elimination, etc.
            # fp-model fast=2: use more aggressive optimizations  when  implementing  float-ing-point calculations.  
            #                  These  optimizations  increase  speed, but may alter the accuracy of floating-point  
            #                  computations.
            # xHost:           Tells the compiler to generate instructions for the highest instruction set
            #                  available on the compilation host processor.
         
            #makefile.write("OPTIONS = -dynamiclib -msse3 -mfpmath=sse -gdwarf-2\n")
          else
            makefile.write("OPTIONS = -shared -msse3 -mfpmath=sse -gdwarf-2\n")
          end
        else
          if beagle?
            makefile.write("OPTIONS = -shared -g\n")
          else
            makefile.write("OPTIONS = -shared -msse3 -mfpmath=sse -g\n")
          end
        end
        if icc
          makefile.write("OPTIONS += -std=c++0x \n")
        else
          makefile.write("OPTIONS += -std=c++11 \n")
        end
        makefile.write("OPTIONS += -stdlib=libc++ # -U__STRICT_ANSI__ -D__STDC_FORMAT_MACROS") if clang
        makefile.write("\n")
        if mac?
          makefile.write("WARNINGS = -Wall -Wno-unknown-pragmas -Wno-trigraphs")
        else
          makefile.write("WARNINGS = -Wall -Wno-unknown-pragmas -Wno-conversion")
        end
        makefile.write("\n")
        makefile.write("DEFINES = -DTT_PLATFORM_MAC\n") if mac?
        makefile.write("DEFINES = -DTT_PLATFORM_LINUX\n") if linux?
        makefile.write("DEFINES = -DTT_PLATFORM_WIN -DWIN32 -D_WINDOWS -D_USRDLL -D_CRT_SECURE_NO_WARNINGS -D_CRT_NOFORCE_MANIFEST -D_STL_NOFORCE_MANIFEST\n") if win32?
        makefile.write("DEFINES += -DTT_PLATFORM_ARM\n") if beagle?

        if defines
          makefile.write("#########################################\n\n")
          i=0
          defines.each do |define|
            define = define.to_s
            makefile.write("DEFINES += -D#{define}\n")
          end
          makefile.write("\n\n")
        end

        makefile.write("\n")
        makefile.write("#########################################\n\n")
        makefile.write("CFLAGS = $(OPTIONS) $(DEFINES) $(INCLUDES) $(WARNINGS)\n")
        if mac?
          makefile.write("CFLAGS += -include#{prefix}\n") if prefix
          makefile.write("LDFLAGS = $(OPTIONS) $(DEFINES) $(LIBS) $(WARNINGS)\n")
          makefile.write("LDFLAGS += -install_name \"#{distropath}/lib/$(NAME).dylib\" \n") if project_type == "library"
          if gcc47
            makefile.write("LDFLAGS += -static-libgcc\n")
          end
        end
        makefile.write("LDFLAGS = $(INCLUDES) $(LIB_INCLUDES) $(LIBS) -g\n") if linux?
        makefile.write("LDFLAGS += -fPIC\n") if beagle?

        if project_type == "library"
          extension_suffix = ".dylib" if mac?
          extension_suffix = ".so" if linux?
          extension_suffix = ".dll" if win32?
        elsif project_type == "implementation"
          extension_suffix = "" if mac? # note that the bundle is a special deal...
          extension_suffix = ".mxe" if win32?
          
          #TODO: binary suffix should depend on the type of implementation we are building!
          
          extension_suffix = "" if linux?          
        else
          extension_suffix = ".ttdylib" if mac?
          extension_suffix = ".ttso" if linux?
          extension_suffix = ".ttdll" if win32?
        end
        
        ######################################################################################################################
        touch_dest = nil;
        build_temp = "build"
        
        if project_type == "library"
          extension_dest = "/usr/local/jamoma/lib" if mac?
        elsif project_type == "implementation"
          if mac?
            extension_dest = "#{path_to_moduleroot}/../#{builddir}/MaxMSP/$(NAME).mxo/Contents/MacOS/"
          end
          extension_dest = "#{path_to_moduleroot_win}\\..\\..\\Builds\\MaxMSP" if win32?

          #TODO: binary destination should depend on the type of implementation we are building!
            
          extension_dest = "/usr/local/jamoma/implementations" if linux?            
        else # extension
          extension_dest = "/usr/local/jamoma/extensions" if mac?
          extension_dest = "/usr/local/lib/jamoma/extensions" if linux?
        end
        
        if project_type == "library"
          extension_dest = "/usr/local/jamoma/lib" if mac?
          extension_dest = "/usr/local/lib/jamoma/lib" if linux?
        elsif project_type == "implementation"
          if mac?
            extension_dest = "#{path_to_moduleroot}/../#{builddir}/MaxMSP/$(NAME).mxo/Contents/MacOS/"
            touch_dest = "#{path_to_moduleroot}/../#{builddir}/MaxMSP/$(NAME).mxo/"
          end
          extension_dest = "#{path_to_moduleroot_win}\\..\\Builds\\MaxMSP" if win32?            
          extension_dest = "/usr/local/jamoma/implementations" if linux?            
        else # extension
          extension_dest = "/usr/local/jamoma/extensions" if mac?
          extension_dest = "/usr/local/lib/jamoma/extensions" if linux?
        end
        
        if (!touch_dest)
          touch_dest = extension_dest
        end
        
        # begin by setting dumb environment variables required for carbon header work correctly on OS 10.8 with Xcode 4.4
        # and GCC
        if mac?
          # First detect if we are in Xcode 4.4, since the environment variables will break the build for Xcode 3
          out = ""
          err = ""
          Open3.popen3("xcodebuild -version") do |stdin, stdout, stderr|
            out = stdout.read
            err = stderr.read
          end
        end
        # {'environment' if (mac? && out.match(/Xcode 4/))}
 
        if mac?
          makefile.write("\n")
          makefile.write("#########################################\n\n")         
          makefile.write("Debug: OPTIMIZATION_FLAGS = $(OPTIMIZATION_DEBUG)\n")
          makefile.write("#Debug: createdirs i386 #{'x64' if arch!='i386'} lipo install\n")
          makefile.write("Debug: createdirs install\n")
          makefile.write("\n")

          makefile.write("Release: OPTIMIZATION_FLAGS = $(OPTIMIZATION_RELEASE)\n")
          makefile.write("Release: createdirs install\n")
          makefile.write("\n")
                                        
          makefile.write("createdirs:\n")
          makefile.write("\tmkdir -p #{build_temp}\n")
          makefile.write("\tmkdir -p #{extension_dest}\n")
          makefile.write("\ttouch #{touch_dest}\n")
          if ($alternate_pkgInfo)
            makefile.write("\tcp #{$alternate_pkgInfo} #{extension_dest}/../PkgInfo\n") if project_type == "implementation"
          else
            makefile.write("\tcp #{path_to_moduleroot}/../../Core/Shared/max/PkgInfo #{extension_dest}/../PkgInfo\n") if project_type == "implementation"
          end
          makefile.write("\n")
          
          # All compiled object files are dependent upon their individual source file and _all_ headers
          # At some point we could try to be more refined about depending on _all_ headers, but for now this is the safest way to go.
          makefile.write("%.i386.o: %.cpp ${INCLUDE_FILES}\n")
          makefile.write("\t$(CC_32) $(CFLAGS) $(OPTIMIZATION_FLAGS) -c $< -o $@\n")
          makefile.write("%.x64.o: %.cpp ${INCLUDE_FILES}\n")
          makefile.write("\t$(CC_64) $(CFLAGS) $(OPTIMIZATION_FLAGS) -c $< -o $@\n")
          makefile.write("%.i386.mm.o: %.mm ${INCLUDE_FILES}\n")
          makefile.write("\t$(CC_32) $(CFLAGS) $(OPTIMIZATION_FLAGS) -c $< -o $@\n")
          makefile.write("%.x64.mm.o: %.mm ${INCLUDE_FILES}\n")
          makefile.write("\t$(CC_64) $(CFLAGS) $(OPTIMIZATION_FLAGS) -c $< -o $@\n")
          makefile.write("\n")
 
          makefile.write("link: i386 #{'x64' if arch!='i386'} | $(SRC32) #{'$(SRC64)' if arch!='i386'}\n\n")
          
          makefile.write("i386: $(SRC32)\n")
          makefile.write("\t$(CC_32) $(LDFLAGS) $(OPTIMIZATION_FLAGS) -o #{build_temp}/$(NAME)-i386#{extension_suffix} $(SRC32)\n")
          makefile.write("\n")

          makefile.write("x64: $(SRC64)\n")
          makefile.write("\t$(CC_64) $(LDFLAGS) $(OPTIMIZATION_FLAGS) -o #{build_temp}/$(NAME)-x86_64#{extension_suffix} $(SRC64)\n")
          makefile.write("\n")

          makefile.write("lipo: | link\n")
          if (arch == 'i386') # not a universal binary, just copy it
            makefile.write("\tcp #{build_temp}/$(NAME)-i386#{extension_suffix} #{build_temp}/$(NAME)#{extension_suffix}\n")           
          else
            makefile.write("\tlipo #{build_temp}/$(NAME)-i386#{extension_suffix} #{build_temp}/$(NAME)-x86_64#{extension_suffix} -create -output #{build_temp}/$(NAME)#{extension_suffix}\n")
          end
          makefile.write("\n")

          makefile.write("clean:\n")
          # this is going be a bit brute-force, but someone else can do some sort of fancy recursive thing to make this better ;-)
          makefile.write("\trm -f $(SRC32) $(SRC64)\n")
          makefile.write("\trm -rf #{build_temp}\n")
          makefile.write("\n")

          makefile.write("install: | lipo\n")
          makefile.write("\t#{"sudo " if linux?}cp #{build_temp}/$(NAME)#{extension_suffix} #{extension_dest}\n")
          if postbuilds
            postbuilds.each do |postbuild|
              postbuild = postbuild.to_s
              makefile.write("\t#{postbuild}\n")
            end
          end
          makefile.write("\n")
             
        else
               
          #################        #################        #################        #################        #################        #################
          #       Debug: 
          #################        #################        #################        #################        #################        #################
          makefile.write("\n")
          makefile.write("#########################################\n\n")         
          makefile.write("Debug:\n")
          makefile.write("\tmkdir -p build\n")
        
          if mac?
            makefile.write("\tmkdir -p #{extension_dest}\n")
            makefile.write("\ttouch #{extension_dest}\n")
            if arch == "i386"
              makefile.write("\t$(CC_32) $(SRC) $(LDFLAGS) $(CFLAGS) $(OPTIMIZATION_DEBUG) -o build/$(NAME)-i386#{extension_suffix}\n")
              makefile.write("\tcp build/$(NAME)-i386#{extension_suffix} build/$(NAME)#{extension_suffix}\n")
            else
              makefile.write("\t$(CC_32) $(SRC) $(LDFLAGS) $(CFLAGS) $(OPTIMIZATION_DEBUG) -o build/$(NAME)-i386#{extension_suffix}\n")
              makefile.write("\t$(CC_64) $(SRC) $(LDFLAGS) $(CFLAGS) $(OPTIMIZATION_DEBUG) -o build/$(NAME)-x86_64#{extension_suffix}\n")
              makefile.write("\tlipo build/$(NAME)-i386#{extension_suffix} build/$(NAME)-x86_64#{extension_suffix} -create -output build/$(NAME)#{extension_suffix}\n")
            end
          else
            makefile.write("\t$(CC) $(SRC) $(LDFLAGS) $(CFLAGS) $(OPTIMIZATION_DEBUG) -o build/$(NAME)#{extension_suffix}\n")
          end

          if project_type == "library"
            extension_dest = "/usr/local/jamoma/lib" if mac?
        		if linux?
              extension_dest = "/usr/local/lib/jamoma/lib"
        		  makefile.write("\tsudo mkdir -p #{extension_dest}\n")
        		end
          elsif project_type == "implementation"
            if mac?
              extension_dest = "#{path_to_moduleroot}/../#{builddir}/MaxMSP/$(NAME).mxo/Contents/MacOS/"
              touch_dest = "#{path_to_moduleroot}/../#{builddir}/MaxMSP/$(NAME).mxo/"
              makefile.write("\tmkdir -p #{extension_dest}\n")
              if ($alternate_pkgInfo)
                makefile.write("\tcp #{$alternate_pkgInfo} #{extension_dest}/../PkgInfo\n")
              else
                makefile.write("\tcp #{path_to_moduleroot}/../../Core/Shared/max/PkgInfo #{extension_dest}/../PkgInfo\n")
              end
              makefile.write("\ttouch #{touch_dest}\n")
            end
            extension_dest = "#{path_to_moduleroot_win}\\..\\Builds\\MaxMSP" if win32?

            #TODO: binary destination should depend on the type of implementation we are building!
            
            extension_dest = "/usr/local/jamoma/implementations" if linux?            
          else # extension
            extension_dest = "/usr/local/jamoma/extensions" if mac?
            extension_dest = "/usr/local/lib/jamoma/extensions" if linux?
          end
        
          makefile.write("\t#{"sudo " if linux?}cp build/$(NAME)#{extension_suffix} #{extension_dest}\n")
          if postbuilds
            postbuilds.each do |postbuild|
              postbuild = postbuild.to_s
              makefile.write("\t#{postbuild}\n")
            end
          end
          #################        #################        #################        #################        #################        #################
          #       Release 
          #################        #################        #################        #################        #################        #################
          makefile.write("\n")
          makefile.write("Release:\n")
          makefile.write("\tmkdir -p build\n")
          if mac?
            makefile.write("\tmkdir -p #{extension_dest}\n")
            if ($alternate_pkgInfo)
              makefile.write("\tcp #{$alternate_pkgInfo} #{extension_dest}/../PkgInfo\n") if project_type == "implementation"
            else
              makefile.write("\tcp #{path_to_moduleroot}/../../Core/Shared/max/PkgInfo #{extension_dest}/../PkgInfo\n") if project_type == "implementation"
            end
          
            if arch == "i386"
              makefile.write("\t$(CC_32) $(SRC) $(LDFLAGS) $(CFLAGS) $(OPTIMIZATION_RELEASE) -o build/$(NAME)-i386#{extension_suffix}\n")
              makefile.write("\tcp build/$(NAME)-i386#{extension_suffix} build/$(NAME)#{extension_suffix}\n")
            else
              makefile.write("\t$(CC_32) $(SRC) $(LDFLAGS) $(CFLAGS) $(OPTIMIZATION_RELEASE) -o build/$(NAME)-i386#{extension_suffix}\n")
              makefile.write("\t$(CC_64) $(SRC) $(LDFLAGS) $(CFLAGS) $(OPTIMIZATION_RELEASE) -o build/$(NAME)-x86_64#{extension_suffix}\n")
              makefile.write("\tlipo build/$(NAME)-i386#{extension_suffix} build/$(NAME)-x86_64#{extension_suffix} -create -output build/$(NAME)#{extension_suffix}\n")
            end
            if project_type == "implementation"
              makefile.write("\ttouch #{touch_dest}\n")
            end
          else
            makefile.write("\t$(CC) $(SRC) $(LDFLAGS) $(CFLAGS) $(OPTIMIZATION_RELEASE) -o build/$(NAME)#{extension_suffix}\n")
          end
   		    makefile.write("\tsudo mkdir -p #{extension_dest}\n") if linux?
          makefile.write("\t#{"sudo " if linux?}cp build/$(NAME)#{extension_suffix} #{extension_dest}\n")
          if postbuilds
            postbuilds.each do |postbuild|
              postbuild = postbuild.to_s
              makefile.write("\t#{postbuild}\n")
            end
          end        
          #################        #################        #################        #################        #################        #################
          #       Clean: 
          #################        #################        #################        #################        #################        #################        
          makefile.write("\n")
          makefile.write("clean:\n")
          makefile.write("\trm -f *.o\n")
          makefile.write("\trm -rf build\n")
          #################        #################        #################        #################        #################        #################
          #       Install: 
          #################        #################        #################        #################        #################        #################        
          makefile.write("\n")
          makefile.write("install:\n")
          makefile.write("\t#{"sudo " if linux?}cp build/$(NAME)#{extension_suffix} #{extension_dest}\n")
          if postbuilds
            postbuilds.each do |postbuild|
              postbuild = postbuild.to_s
              makefile.write("\t#{postbuild}\n")
            end
          end
        end
 
      end # big new if mac? statement
  
      if win32?
  	    vcproj_toolfiles = Element.new("ToolFiles")
  	    vcproj_root.add_element(vcproj_toolfiles)
	  
        vcproj_configurations = Element.new("Configurations")
        vcproj_configurations.add_element(vcproj_release)
        vcproj_configurations.add_element(vcproj_debug)
        vcproj_root.add_element(vcproj_configurations)
      
        vcproj_refs = Element.new("References")
    	  vcproj_root.add_element(vcproj_refs)
    
  	    vcproj_root.add_element(vcproj_files)
	  
        vcproj_globs = Element.new("Globals")
    	  vcproj_root.add_element(vcproj_globs)
	  

        # WRITE THE VCPROJ FILE ########################
        #f = File.new(filepath, "w")
        f = File.new("#{projectdir}/#{projectname}.vcproj", "w")
        formatter = REXML::Formatters::Pretty.new
        s = ""

        vcproj << XMLDecl.new("1.0", "UTF-8")

        formatter.write vcproj, s
        # puts s

        # Now that we have the XML, perform additional substitutions
        s.gsub!(/\#(\S*)/, '<o>\1</o>')

        f.write(s)
        f.close
        # WRITE THE VCPROJ FILE ########################
      
        winpath = "#{Dir.pwd}/#{projectdir}/#{projectname}.vcproj"
  	    #puts "cygwin path: #{winpath}"
  	    winpath = `cygpath -w #{winpath}`
  	    winpath.gsub!(/(\n)/,'')
  	    #puts "winpath: #{winpath}"
        `vcbuild /upgrade "#{winpath}"` 
      else
        makefile.flush
        makefile.close
        makefile_generated = true
      end
    end
    
    return makefile_generated
  end
  
  
  def find_and_build_project(projectdir, configuration, clean, forcedCompiler, distropath)
    foldername = projectdir.split("/").last
    use_make = generate_makefile(projectdir, foldername, forcedCompiler)
    
    # First look for a YAML project config file
    # If one exists, then we need to first generate the platform-specific project files using CMake
    #
    # A global called $g_use_yaml_project_files must be turned-on at the top of this file though...
    #
    # How do we deal with iOS here?
    # TODO: switch Windows to GCC
    #
    
    # fall back on a custom Makefile (e.g. for tap.loader)
    if (!use_make && !File.exists?("#{projectdir}/#{foldername}.xcodeproj") && mac?)
      use_make = true
    end
    
    if projectdir == "jcom.in~" || projectdir == "jcom.out~" || projectdir == "jcom.parameter"
      clean = true
    end
    
    if win32?
      rgx = /.vcproj$/
    elsif linux?
      rgx = /Makefile/
    else
      rgx = /.xcodeproj$/
    end
    rgx = /Makefile/ if use_make

    Dir.foreach(projectdir) do |file|
      if rgx.match(file)
        build_project(projectdir, file, configuration, clean, distropath, use_make)
      end
    end
 
  end

  
  def find_and_copy_helpfile(filedir, dstdir)

    	rgx = /.maxhelp/
    Dir.foreach(filedir) do |file|      
      if rgx.match(file)
          copy_helpfile(file, filedir, dstdir)
      end
    end 
  end


  def build_dir(dir, configuration, clean, forcedCompiler, distropath=nil)
    dir = "#{@svn_root}/#{dir}"
    return if !FileTest.exist?(dir) || !FileTest.directory?(dir)

    Dir.foreach(dir) do |subf|
      next if /^\./.match(subf)
      next if /common/.match(subf)
      next if !FileTest.directory?("#{dir}/#{subf}")
      find_and_build_project("#{dir}/#{subf}", configuration, clean, forcedCompiler, distropath)
    end
  end   


  def maxhelp_dir(dir, dstdir)
    dir = "#{@svn_root}/#{dir}"
    return if !FileTest.exist?(dir) || !FileTest.directory?(dir)     
    Dir.foreach(dir) do |subf|
      next if /^\./.match(subf)
      next if /common/.match(subf)
      next if !FileTest.directory?("#{dir}/#{subf}")     
      find_and_copy_helpfile("#{dir}/#{subf}", dstdir) 
    end
  end
  
  
  def create_audiograph_objectmappings(filedir)
    return if !FileTest.exist?(filedir) || !FileTest.directory?(filedir)
	
	local_dir = Dir.pwd
    Dir.chdir(filedir)
    objectmappings = File.new("jamoma-objectmappings.txt", 'w')
    database = File.new("jamoma-database.txt", 'w')
	
    rgx = /=.mxe/

    Dir.foreach(filedir) do |file|
      if rgx.match(file)
        #  puts "found " + file
        basename = File.basename(file, ".mxe")
        objectmappings.puts "max objectfile " + basename.gsub("=","≈") + " " + basename + ";"
        database.puts "max db.addvirtual alias " + basename.gsub("=","≈") + " " + basename + ";"
      end
    end
	
    objectmappings.close
    database.close
    Dir.chdir(local_dir)
  end

end

require 'library'

# Instructions:
# Suites and runs support the "profile" reserved keyword under the 
# YAML configuration file. That profile name matches a module 
# defined here. And since module names must have a capital letter
# so too must the profiles be named.
#
# Suites and Runs expose specific methods to the user that must
# be specified in library.rb.  However there could be multiple
# versions of anyone of those methods. Using ruby's alias
# within the module allows one to specify which of those
# methods should be mapped to the expected interface
#
# Runs require the following methods:
# lib_build_prep
# lib_build
# lib_build_post
# lib_data
# lib_run_prep
# lib_run
# lib_run_post
# lib_re_srt_success
# lib_outfiles
#
# Suites require the following methods:
# lib_suite_prep
# lib_suite_post
#
# Library is the module that contains all methods 
# defined within library.rb and as such must be 
# included with every "Profile" module
# Use the syntax=> alias <new_name> <old_name>
# to define the method mapping within the modules
# Only those methods that do not exist in their
# expected names must be aliased
# ex:
# module SVNProfile
#   include Library
#   alias lib_build_prep lib_build_prep_svnrepo
# end
# module GitProfile
#   include Library  
#   alias lib_build_prep lib_build_prep_gitrepo

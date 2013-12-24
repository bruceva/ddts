require 'library'

module Mock

   include Library

   alias lib_build_prep lib_build_prep_mock
   alias lib_build lib_build_mock
   alias lib_build_post lib_build_post_mock
   alias lib_data lib_data_mock
   alias lib_run_prep lib_run_prep_mock
   alias lib_run lib_run_mock
   alias re_str_success re_str_success_mock

end

module Nightly

   include Library

   alias lib_build_prep lib_build_prep_common
   alias lib_build lib_build_common
   alias lib_build_post lib_build_post_common
   alias lib_data lib_data_common
   alias lib_run_prep lib_run_prep_common
   alias lib_run lib_run_mock
   alias re_str_success re_str_success_mock

end

module Weekly

   include Library

   alias lib_build_prep lib_build_prep_common
   alias lib_build lib_build_common
   alias lib_build_post lib_build_post_common
   alias lib_data lib_data_common
   alias lib_run_prep lib_run_prep_common
   alias lib_run lib_run_batch
   alias lib_outfiles lib_outfiles_batch
   alias lib_queue_del_cmd lib_queue_del_cmd_batch
   alias re_str_success re_str_success_batch
end

#module Suite

#  include Library

#  alias lib_suite_post lib_suite_post_common
#  alias lib_suite_prep lib_suite_prep_common

#end



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

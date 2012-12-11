use strict;
use warnings;
use 5.008;

use Module::Build;

Module::Build->new(
  module_name        => 'Win32::Readch',
  license            => 'perl',
  configure_requires => { 'Module::Build' => 0 },
  requires           => { 'Win32::Console' => 0,
                          'Win32::IPC' => 0 },
  dist_abstract      => 'Read individual characters from the keyboard using Win32::Console',
)->create_build_script;

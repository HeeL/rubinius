require 'rakelib/rubinius'
require 'rakelib/build'
require 'rakelib/instruction_parser'
require 'rakelib/generator_task'

require 'tmpdir'
require 'ostruct'

config = OpenStruct.new
config.use_jit = true
config.compile_with_llvm = false

CONFIG = config
DEV_NULL = RUBY_PLATFORM =~ /mingw|mswin/ ? 'NUL' : '/dev/null'
VM_EXE = RUBY_PLATFORM =~ /mingw|mswin/ ? 'vm/vm.exe' : 'vm/vm'

############################################################
# Files, Flags, & Constants

encoding_database = "vm/gen/encoding_database.cpp"

ENV.delete 'CDPATH' # confuses llvm_config

INSN_GEN    = %w[ vm/gen/instruction_names.cpp
                  vm/gen/instruction_names.hpp
                  vm/gen/instruction_sizes.hpp
                  vm/gen/instruction_prototypes.hpp
                  vm/gen/instruction_defines.hpp
                  vm/gen/instruction_locations.hpp
                  vm/gen/instruction_implementations.hpp
                  vm/gen/instruction_visitors.hpp
                  vm/gen/instruction_effects.hpp
                  web/_includes/instructions.markdown
                ]
TYPE_GEN    = %w[ vm/gen/includes.hpp
                  vm/gen/kind_of.hpp
                  vm/gen/object_types.hpp
                  vm/gen/typechecks.gen.cpp
                  vm/gen/primitives_declare.hpp
                  vm/gen/primitives_glue.gen.cpp ]

GENERATED = %W[ vm/gen/revision.h
                vm/gen/config_variables.h
                #{encoding_database} ] + TYPE_GEN + INSN_GEN

# Files are in order based on dependencies. For example,
# CompactLookupTable inherits from Tuple, so the header
# for compactlookuptable.hpp has to come after tuple.hpp
field_extract_headers = %w[
  vm/builtin/basicobject.hpp
  vm/builtin/object.hpp
  vm/builtin/integer.hpp
  vm/builtin/fixnum.hpp
  vm/builtin/array.hpp
  vm/builtin/bignum.hpp
  vm/builtin/executable.hpp
  vm/builtin/access_variable.hpp
  vm/builtin/alias.hpp
  vm/builtin/block_environment.hpp
  vm/builtin/block_as_method.hpp
  vm/builtin/bytearray.hpp
  vm/builtin/chararray.hpp
  vm/builtin/io.hpp
  vm/builtin/channel.hpp
  vm/builtin/module.hpp
  vm/builtin/class.hpp
  vm/builtin/compiledmethod.hpp
  vm/builtin/data.hpp
  vm/builtin/dir.hpp
  vm/builtin/exception.hpp
  vm/builtin/float.hpp
  vm/builtin/immediates.hpp
  vm/builtin/iseq.hpp
  vm/builtin/list.hpp
  vm/builtin/lookuptable.hpp
  vm/builtin/ffi_pointer.hpp
  vm/builtin/methodtable.hpp
  vm/builtin/nativefunction.hpp
  vm/builtin/packed_object.hpp
  vm/builtin/randomizer.hpp
  vm/builtin/regexp.hpp
  vm/builtin/staticscope.hpp
  vm/builtin/string.hpp
  vm/builtin/symbol.hpp
  vm/builtin/thread.hpp
  vm/builtin/tuple.hpp
  vm/builtin/compactlookuptable.hpp
  vm/builtin/time.hpp
  vm/builtin/nativemethod.hpp
  vm/builtin/system.hpp
  vm/builtin/autoload.hpp
  vm/builtin/proc.hpp
  vm/builtin/variable_scope.hpp
  vm/builtin/location.hpp
  vm/builtin/capi_handle.hpp
  vm/builtin/global_cache_entry.hpp
  vm/builtin/weakref.hpp
  vm/builtin/fiber.hpp
  vm/builtin/thunk.hpp
  vm/builtin/call_unit.hpp
  vm/builtin/call_unit_adapter.hpp
  vm/builtin/cache.hpp
  vm/builtin/encoding.hpp
  vm/builtin/atomic.hpp
]

############################################################
# Other Tasks

# Build options.
namespace :build do

  desc "Build LLVM"
  task :llvm do
    if Rubinius::BUILD_CONFIG[:llvm] == :svn
      unless File.file?("vendor/llvm/Release/bin/llvm-config")
        ENV["REQUIRES_RTTI"] = "1"
        Dir.chdir "vendor/llvm" do
          sh %[sh -c "#{expand("./configure")} #{llvm_config_flags}"]
          sh make
        end
      end
    end
  end

  # Issue the actual build commands. NEVER USE DIRECTLY.
  task :build => %W[
                     build:llvm
                     #{VM_EXE}
                     kernel:build
                     build:ffi:preprocessor
                     build:zlib
                     extensions
                   ]

  namespace :ffi do

    FFI_PREPROCESSABLES = %w[ lib/fcntl.rb
                              lib/zlib.rb
                            ]

    unless BUILD_CONFIG[:windows]
      FFI_PREPROCESSABLES.concat %w[ lib/etc.rb
                                     lib/syslog.rb
                                   ]
    end

    # Generate the .rb files from lib/*.rb.ffi
    task :preprocessor => FFI_PREPROCESSABLES

    FFI::FileProcessor::Task.new FFI_PREPROCESSABLES

  end

  if Rubinius::BUILD_CONFIG[:vendor_zlib]
    directory 'lib/zlib'

    task :zlib => ['lib/zlib', VM_EXE] do
      FileList["vendor/zlib/libz.*"].each do |lib|
        cp lib, 'lib/zlib/'
      end
    end
  else
    task :zlib
  end
end

# Compilation tasks

def files(targets, dependencies=nil, &block)
  targets.each do |target|
    if dependencies then
      file target => dependencies, &block
    else
      file target, &block
    end
  end
end

directory "vm/gen"

file 'vm/codegen/field_extract.rb'    => 'vm/gen'

task :run_field_extract do
  ruby 'vm/codegen/field_extract.rb', *field_extract_headers
end

files TYPE_GEN, field_extract_headers + %w[vm/codegen/field_extract.rb] + [:run_field_extract] do
end

file encoding_database => 'vm/codegen/encoding_extract.rb' do |t|
  dir = File.expand_path "../vendor/onig"
  ruby 'vm/codegen/encoding_extract.rb', dir, t.name
end

task 'vm/gen/revision.h' do |t|
  git_dir = File.expand_path "../../.git", __FILE__

  if !ENV['RELEASE'] and File.directory? git_dir
    buildrev = `git rev-parse HEAD`.chomp
  else
    buildrev = "release"
  end

  File.open t.name, "wb" do |f|
    f.puts %[#define RBX_BUILD_REV     "#{buildrev}"]
  end
end

file 'vm/gen/config_variables.h' => %w[lib/rubinius/configuration.rb config.rb] do |t|
  puts "GEN #{t.name}"
  ruby 'vm/codegen/config_vars.rb', t.name
end

require 'projects/daedalus/daedalus'

if jobs = ENV['JOBS']
  @parallel_jobs = jobs.to_i
  if @parallel_jobs < 1
    STDERR.puts "Illegal number of parallel jobs: #{jobs}. Setting to 1."
    @parallel_jobs = 1
  end
elsif File.exists? ".be_gentle"
  @parallel_jobs = 1
else
  @parallel_jobs = nil
end

task VM_EXE => GENERATED do
  blueprint = Daedalus.load "rakelib/blueprint.rb"
  blueprint.build VM_EXE, @parallel_jobs
end

task 'vm/test/runner' => GENERATED do
  blueprint = Daedalus.load "rakelib/blueprint.rb"
  blueprint.build "vm/test/runner", @parallel_jobs
end

# Generate files for instructions and interpreters

file 'vm/gen/primitives_glue.gen.cpp' => field_extract_headers

iparser = InstructionParser.new "vm/instructions.def"

def generate_instruction_file(parser, generator, name)
  puts "GEN #{name}"
  parser.parse
  parser.send generator, name
end

insn_deps = %w[  vm/gen
                 vm/instructions.def
                 rakelib/instruction_parser.rb
              ]

file "lib/compiler/opcodes.rb" => insn_deps do |t|
  generate_instruction_file iparser, :generate_opcodes, t.name
end

file "lib/compiler/generator_methods.rb" => insn_deps do |t|
  generate_instruction_file iparser, :generate_generator_methods, t.name
end

file "vm/gen/instruction_names.hpp" => insn_deps do |t|
  generate_instruction_file iparser, :generate_names_header, t.name
end

file "vm/gen/instruction_names.cpp" => insn_deps do |t|
  generate_instruction_file iparser, :generate_names, t.name
end

file "vm/gen/instruction_prototypes.hpp" => insn_deps do |t|
  generate_instruction_file iparser, :generate_prototypes, t.name
end

file "vm/gen/instruction_sizes.hpp" => insn_deps do |t|
  generate_instruction_file iparser, :generate_sizes, t.name
end

file "vm/gen/instruction_defines.hpp" => insn_deps do |t|
  generate_instruction_file iparser, :generate_defines, t.name
end

file "vm/gen/instruction_locations.hpp" => insn_deps do |t|
  generate_instruction_file iparser, :generate_locations, t.name
end

file "vm/gen/instruction_implementations.hpp" => insn_deps do |t|
  generate_instruction_file iparser, :generate_implementations , t.name
end

file "vm/gen/instruction_visitors.hpp" => insn_deps do |t|
  generate_instruction_file iparser, :generate_visitors, t.name
end

file "vm/gen/instruction_effects.hpp" => insn_deps do |t|
  generate_instruction_file iparser, :generate_stack_effects, t.name
end

file "web/_includes/instructions.markdown" => insn_deps do |t|
  generate_instruction_file iparser, :generate_documentation, t.name
end

namespace :vm do
  desc 'Run all VM tests.  Uses its argument as a filter of tests to run.'
  task :test, :filter do |task, args|
    ENV['SUITE'] = args[:filter] if args[:filter]
    ENV['VERBOSE'] = '1' if $verbose
    sh 'vm/test/runner', :verbose => $verbose
  end

  task :test => %w[ vm/test/runner ]

  desc "Clean up vm build files"
  task :clean do
    blueprint = Daedalus.load "rakelib/blueprint.rb"
    files = FileList[
      GENERATED,
      'vm/gen/*',
      'vm/test/runner',
      'vm/test/runner.cpp',
      'vm/test/runner.o',
      VM_EXE,
      'vm/.deps',
      'lib/zlib/*',
      'lib/zlib'
    ].exclude("vm/gen/config.h")

    files.each do |filename|
      rm_rf filename, :verbose => $verbose
    end

    blueprint.clean
  end

  desc "Clean up, including all external libs"
  task :distclean => :clean

  desc "Show which primitives are missing"
  task :missing_primitives do
    kernel_files = FileList['kernel/**/*.rb'].join " "
    kernel_primitives = `grep 'Rubinius.primitive' #{kernel_files} | awk '{ print $3 }'`
    kernel_primitives = kernel_primitives.gsub(':', '').split("\n").sort.uniq

    cpp_primitives = `grep 'Rubinius.primitive' vm/builtin/*.hpp | awk '{ print $4 }'`
    cpp_primitives = cpp_primitives.gsub(':', '').split("\n").sort.uniq

    missing = kernel_primitives - cpp_primitives

    puts missing.join("\n")
  end
end

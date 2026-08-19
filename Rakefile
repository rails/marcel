require 'bundler/gem_tasks'
require 'fileutils'
require 'rake/testtask'
require 'rbconfig'
require 'tempfile'

task default: [ :test, "tables:check" ]

Rake::TestTask.new :test do |t|
  t.libs << "test"
  t.test_files = FileList['test/**/*_test.rb']
end

namespace :test do
  task tables: [ :tables, :test ]
  task update: [ :update, :test ]
end


task :types do
  fixture_path = File.expand_path("../test/fixtures", __FILE__)

  tested_by_data = Dir["#{fixture_path}/magic/*/*"].map do |path|
    type = path.split("#{fixture_path}/magic/").last
  end

  tested_by_filename = Dir["#{fixture_path}/name/*/*"].sort.map do |path|
    type = path.split("#{fixture_path}/name/").last
    extensions = Dir["#{path}/*.*"].map { |file| File.extname(file) }
    [type, extensions]
  end

  puts "Test fixtures exist for the following types: "

  tested_by_filename.each do |(type, extensions)|
    if tested_by_data.include?(type)
      puts "    #{type} by (#{extensions.join(", ")}) and by file data"
    else
      puts "    #{type} by (#{extensions.join(", ")})"
    end
  end
end

desc "Download pinned Tika data and update data tables"
task update: [ "tika:download", "tables" ]

desc "Generate data tables"
task :tables do
  atomically_replace "lib/marcel/tables.rb" do |temporary_path|
    generate_tables temporary_path
  end
end

namespace :tables do
  desc "Verify that committed data tables match their XML sources"
  task :check do
    Tempfile.create([ "marcel-tables", ".rb" ]) do |temporary|
      temporary.close
      generate_tables temporary.path

      unless FileUtils.compare_file(temporary.path, "lib/marcel/tables.rb")
        abort "lib/marcel/tables.rb is stale; run `bundle exec rake tables`"
      end
    end
  end
end

namespace :tika do
  desc "Download pinned data/tika.xml"
  task :download do
    atomically_replace "data/tika.xml" do |temporary_path|
      sh "script/download_tika_data.rb", out: temporary_path
    end
  end
end

def atomically_replace(destination)
  mode = File.exist?(destination) ? File.stat(destination).mode & 0o777 : 0o644

  Tempfile.create([ File.basename(destination), ".tmp" ], File.dirname(destination)) do |temporary|
    temporary_path = temporary.path
    temporary.close
    yield temporary_path
    File.chmod(mode, temporary_path)
    File.rename(temporary_path, destination)
  end
end

def generate_tables(destination)
  sh "script/download_tika_data.rb", "--verify", "data/tika.xml"
  sh "script/generate_tables.rb", "--output", destination, "data/tika.xml", "data/custom.xml"
  sh RbConfig.ruby, "-c", destination
end

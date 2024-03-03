require 'bundler/gem_tasks'
require 'rake/testtask'

task default: :test

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

desc "Download latest Tika data and update data tables"
task update: [ "tika:download", "tables" ]

desc "Generate data tables"
task tables: "lib/marcel/tables.rb"
file "lib/marcel/tables.rb" => %w[ data/tika.xml data/custom.xml ] do |target|
  sh "script/generate_tables.rb", *target.prerequisites, out: target.name
end

namespace :tika do
  desc "Download latest data/tika.xml"
  task :download do
    sh "script/download_tika_data.rb", out: "data/tika.xml"
  end
end

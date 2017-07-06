require 'bundler/gem_tasks'
require 'rake/testtask'

Rake::TestTask.new do |t|
  t.libs << "test"
  t.test_files = FileList['test/**/*_test.rb']
end

task default: :test

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

require "minitest/test_task"

Minitest::TestTask.create

task :default => :test

task :build_hooks do
  FileUtils.mkdir_p("hooks")

  Dir.glob("lib/*_hook.rb").each do |hook_rb|
    filename = File.basename(hook_rb, ".rb")
    classname = filename.split("_").map(&:capitalize).join("")
    hookname = filename.gsub("_hook", "").tr("_", "-")
    File.open("hooks/#{hookname}", "w+") do |f|
      f.write <<~HERE
      #!/usr/bin/env ruby

      require_relative "../lib/startup.rb"
      
      #{classname}.new.run(ARGV)
      HERE
    end

    system("chmod +x hooks/#{hookname}")
  end
end

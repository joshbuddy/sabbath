# encoding: utf-8

begin
  require 'jeweler'
  Jeweler::Tasks.new do |s|
    s.name = "sabbath"
    s.description = s.summary = "Rest for your work (queues)"
    s.email = "joshbuddy@gmail.com"
    s.homepage = "http://github.com/joshbuddy/sabbath"
    s.authors = ["Joshua Hull"].sort
    s.files = FileList["[A-Z]*", "{lib,bin,examples}/**/*"]
    s.add_dependency 'thin'
    s.add_dependency 'eventmachine'
    s.add_dependency 'em-beanstalk', '>=0.0.6'
    s.add_dependency 'rack'
    s.add_dependency 'usher'
    s.add_dependency 'json'
    s.add_dependency 'uuid'
  end
  Jeweler::GemcutterTasks.new
rescue LoadError
  puts "Jeweler not available. Install it with: sudo gem install technicalpickles-jeweler -s http://gems.github.com"
end

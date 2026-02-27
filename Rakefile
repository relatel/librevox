# frozen_string_literal: true

require 'rake/testtask'
require "bundler/gem_tasks"

Rake::TestTask.new do |t|
  t.libs << "lib"
  t.test_files = FileList['test/**/*_test.rb']
end

task :version do
  require_relative "lib/librevox/version"

  print Librevox::VERSION
end

task :default => :test

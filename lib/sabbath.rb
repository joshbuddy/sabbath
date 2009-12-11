require 'thin'
require 'rack'
require 'usher'
require 'json'
require 'uuid'

$LOAD_PATH << File.dirname(__FILE__)

require 'sabbath/server'
require 'sabbath/backend'

class Sabbath
  
  attr_reader :options
  
  def initialize(options)
    @options = options
    @backend = Backend::Beanstalk.new(options[:host], options[:port])
  end
  
  def start
    Server.new(@backend, options[:web_host], options[:web_port], options[:rackup]).start
  end
  
end
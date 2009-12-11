require 'em-beanstalk'

class Sabbath
  class Backend
    class Beanstalk
      
      attr_reader :host, :port

      Name = 'Beanstalkd'.freeze
      
      def name
        Name
      end
      
      def initialize(host, port)
        @host, @port = host, port
        @conns = {}
      end
      
      def connection(id, tube = 'default')
        @conns[id] ||= EM::Beanstalk.new(:host => host, :port => port, :tube => tube, :retry_count => 0, :raise_on_disconnect => false)
      end
      
      def get_latest_job(conn_id, tube, timeout = nil, &block)
        connection(conn_id, tube).reserve(timeout, &block)
      end
      
      def get_job(conn_idtube, id, &block)
        connection(conn_id, tube).peek(id, &block)
      end
      
      def create_job(conn_id, tube, body, &block)
        connection(conn_id, tube).put(body, &block)
      end
      
      def delete_job(conn_id, tube, id, &block)
        puts "deleting job #{tube.inspect} #{id.inspect}"
        connection(conn_id, tube).delete(id, &block)
      end
      
    end
  end
end
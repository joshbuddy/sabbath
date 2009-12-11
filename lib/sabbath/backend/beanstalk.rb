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
      end
      
      def connection
        conn = EM::Beanstalk.new(:host => host, :port => port)
      end
      
      def get_latest_job(tube, timeout = nil)
        conn = connection
        conn.watch(tube) {
          conn.reserve(timeout) { |job|
            yield job
          }
        }
      end
      
      def get_job(tube, id)
        conn = connection
        conn.watch(tube) {
          conn.peek(id) { |job|
            yield job
          }
        }
      end
      
      def create_job(tube, body)
        conn = connection
        conn.use(tube) {
          conn.put(tube, body) { |id|
            yield id
          }
        }
      end
      
      def delete_job(tube, id)
        conn = connection
        conn.use(tube) {
          conn.delete(id) {
            yield
          }
        }
      end
      
    end
  end
end
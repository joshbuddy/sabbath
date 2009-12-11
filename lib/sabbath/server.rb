module Thin
  class Server
    # Start the server and listen for connections.
    def start
      raise ArgumentError, 'app required' unless @app
      
      log   ">> Sabbath ---> connected to #{app.backend.name} on port #{app.backend.port}, host #{app.backend.host}"
      log   ">> Using Thin web server (v#{VERSION::STRING} codename #{VERSION::CODENAME})"
      debug ">> Debugging ON"
      trace ">> Tracing ON"
      
      log ">> Maximum connections set to #{@backend.maximum_connections}"
      log ">> Listening on #{@backend}, CTRL+C to stop"
      
      @backend.start
    end
    alias :start! :start
  end
end

class Sabbath
  class Server

    class DeferrableBody
      include EventMachine::Deferrable

      def call(body)
        body.each do |chunk|
          @body_callback.call(chunk)
        end
      end

      def each(&blk)
        @body_callback = blk
      end
      
      def succeed_with(body)
        call(Array(body.to_json))
        succeed
      end
      
    end

    AsyncResponse = [-1, {}, []].freeze
    
    attr_reader :backend, :web_host, :web_port
    
    def initialize(backend, web_host, web_port)
      @backend = backend
      @web_host, @web_port = web_host, web_port
      @router = Usher.new(:request_methods => [:request_method], :delimiters => ['/', '.'])
      @router.add_route('/:tube(/)',        :conditions => {:request_method => 'GET'})      .name(:get_latest_job)
      @router.add_route('/:tube/:job_id',   :conditions => {:request_method => 'GET'})      .name(:get_job)
      @router.add_route('/:tube',           :conditions => {:request_method => 'POST'})     .name(:create_job)
      @router.add_route('/:tube/:job_id',   :conditions => {:request_method => 'DELETE'})   .name(:delete_job)
    end
    
    def call(env)
      
      body = DeferrableBody.new

      # Get the headers out there asap, let the client know we're alive...
      EventMachine::next_tick {
        request = Rack::Request.new(env)
        query_params = Rack::Utils.parse_query(request.query_string)
        case response = @router.recognize(request)
        when nil
          env['async.callback'].call([404, {}, []])
        else
          params = response.params_as_hash
          case response.path.route.named
          when :get_latest_job
            env['async.callback'].call([200, {'Content-Type' => 'text/plain'}, body])
            backend.get_latest_job(params[:tube], params['timeout']) {|job|
              body.succeed_with(:id => job.id, :body => job.body)
            }.error {|message|
              body.succeed_with(:error => message)
            }
          when :get_job
            env['async.callback'].call([200, {'Content-Type' => 'text/plain'}, body])
            backend.get_job(params[:tube], params[:job_id]) {|job|
              body.succeed_with(:id => job.id, :body => job.body)
            }.error {|message|
              body.succeed_with(:error => message)
            }
          when :create_job
            env['async.callback'].call([200, {'Content-Type' => 'text/plain'}, body])
            backend.create_job(params[:tube], request.body.to_s) {|id|
              body.succeed_with(:id => id)
            }.error {|message|
              body.succeed_with(:error => message)
            }
          when :delete_job
            env['async.callback'].call([200, {'Content-Type' => 'text/plain'}, body])
            backend.delete_job(params[:tube], params[:job_id]) {|id|
              body.succeed_with(:success => true)
            }.error {|message|
              body.succeed_with(:error => message)
            }
          end
        end
      }
      AsyncResponse
    end
    
    def start
      @server = self
      EM.run do
        Thin::Server.start(web_host, web_port, self)
      end      
    end
  end
end



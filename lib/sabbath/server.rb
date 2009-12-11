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

      attr_accessor :jsonp_callback

      def call(body)
        body.each do |chunk|
          @body_callback.call(chunk)
        end
      end

      def each(&blk)
        @body_callback = blk
      end
      
      def succeed_with(body)
        data = if jsonp_callback 
          "#{jsonp_callback}(#{body.to_json})"
        else
          body.to_json
        end
        
        puts "sending #{data.inspect}"
        call(Array(data))
        succeed
      end
      
      
    end

    AsyncResponse = [-1, {}, []].freeze
    
    attr_reader :backend, :web_host, :web_port, :cookie_name
    
    def initialize(backend, web_host, web_port, cookie_name = 'sabbath_id')
      @backend = backend
      @web_host, @web_port, @cookie_name = web_host, web_port, cookie_name
      @router = Usher.new(:request_methods => [:request_method], :delimiters => ['/', '.'])
      @router.add_route('/:tube',                   :conditions => {:request_method => 'GET'})      .name(:get_latest_job)
      @router.add_route('/:tube/:job_id',           :conditions => {:request_method => 'GET'})      .name(:get_job)
      @router.add_route('/:tube',                   :conditions => {:request_method => 'POST'})     .name(:create_job)
      @router.add_route('/:tube/:job_id',           :conditions => {:request_method => 'DELETE'})   .name(:delete_job)
      @router.add_route('/:tube/:job_id/release',   :conditions => {:request_method => 'PUT'})      .name(:release_job)
    end
    
    def call(env)
      request = Rack::Request.new(env)
      query_params = Rack::Utils.parse_query(request.query_string)
      env['REQUEST_METHOD'] = query_params['_method'].upcase if query_params['_method']
      
      id = request.cookies[cookie_name] || UUID.new.generate
      p id
      common_response_headers = {'Content-Type' => 'text/javascript'}
      
      common_response_headers['Set-cookie'] = Rack::Utils.build_query(cookie_name => id) unless request.cookies[cookie_name]
      
      body = DeferrableBody.new
      # Get the headers out there asap, let the client know we're alive...
      EventMachine::next_tick {
        body.jsonp_callback = query_params['callback']
        case response = @router.recognize(request)
        when nil
          env['async.callback'].call([404, {}, []])
        else
          params = response.params_as_hash
          case response.path.route.named
          when :get_latest_job
            puts "latest job..."
            env['async.callback'].call([200, common_response_headers, body])
            backend.get_latest_job(id, params[:tube], params['timeout']) {|job|
              puts "sending job.body: #{job.body}"
              body.succeed_with(:id => job.id, :body => job.body)
            }.on_error {|message|
              puts "message.. #{message}"
              body.succeed_with(:error => message)
            }
          when :get_job
            env['async.callback'].call([200, common_response_headers, body])
            backend.get_job(id, params[:tube], params[:job_id]) {|job|
              body.succeed_with(:id => job.id, :body => job.body)
            }.on_error {|message|
              body.succeed_with(:error => message)
            }
          when :create_job
            env['async.callback'].call([200, common_response_headers, body])
            backend.create_job(id, params[:tube], query_params['body']) {|id|
              body.succeed_with(:id => id)
            }.on_error {|message|
              body.succeed_with(:error => message)
            }
          when :delete_job
            env['async.callback'].call([200, common_response_headers, body])
            backend.delete_job(id, params[:tube], params[:job_id]) {
              body.succeed_with(:success => true)
            }.on_error {|message|
              body.succeed_with(:error => message)
            }
          when :release_job
            env['async.callback'].call([200, common_response_headers, body])
            backend.release_job(id, params[:tube], params[:job_id]) {
              body.succeed_with(:success => true)
            }.on_error {|message|
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



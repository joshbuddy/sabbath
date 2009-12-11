module Thin
  class Server
    # Start the server and listen for connections.
    def start
      raise ArgumentError, 'app required' unless @app
      
      log   ">> Sabbath ---> connected to #{app.name} on port #{app.port}, host #{app.host}"
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

    class MethodOverride
      HTTP_METHODS = %w(GET HEAD PUT POST DELETE OPTIONS)

      METHOD_OVERRIDE_PARAM_KEY = "_method".freeze
      HTTP_METHOD_OVERRIDE_HEADER = "HTTP_X_HTTP_METHOD_OVERRIDE".freeze

      def initialize(app)
        @app = app
      end

      def call(env)
        request = Rack::Request.new(env)
        query_params = Rack::Utils.parse_query(request.query_string)
        method = query_params[METHOD_OVERRIDE_PARAM_KEY]
        method = method.to_s.upcase
        if HTTP_METHODS.include?(method)
          env["rack.methodoverride.original_method"] = env["REQUEST_METHOD"]
          env["REQUEST_METHOD"] = method
        end

        @app.call(env)
      end
    end
    
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
    
    class StatsProvider
      attr_reader :name, :host, :port
      def initialize(app, name, host, port)
        @app, @name, @host, @port = app, name, host, port
      end
      def call(env); @app.call(env); end
    end
    
    attr_reader :backend, :web_host, :web_port, :cookie_name, :rackup
    
    def initialize(backend, web_host, web_port, rackup, cookie_name = 'sabbath_id')
      @backend = backend
      @web_host, @web_port, @cookie_name, @rackup = web_host, web_port, cookie_name, rackup
      @router = Usher.new(:request_methods => [:request_method], :delimiters => ['/', '.'])
      @router.add_route('/:tube',                   :conditions => {:request_method => 'GET'})      .name(:get_latest_job)
      @router.add_route('/:tube/:job_id',           :conditions => {:request_method => 'GET'})      .name(:get_job)
      @router.add_route('/:tube',                   :conditions => {:request_method => 'POST'})     .name(:create_job)
      @router.add_route('/:tube/:job_id',           :conditions => {:request_method => 'DELETE'})   .name(:delete_job)
      @router.add_route('/:tube/:job_id/release',   :conditions => {:request_method => 'PUT'})      .name(:release_job)
    end
    
    def builder
      builder = Rack::Builder.new
      builder.use(StatsProvider, backend.name, backend.host, backend.port)
      builder.instance_eval(File.read(rackup)) if rackup
      builder.use(MethodOverride)
      builder.run(self)
      builder
    end
    
    def call(env)
      p env
      request = Rack::Request.new(env)
      query_params = Rack::Utils.parse_query(request.query_string)
      
      id = request.cookies[cookie_name] || UUID.new.generate
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
          params = Hash[response.params]
          p response.path.route.named
          p params
          case response.path.route.named
          when :get_latest_job
            env['async.callback'].call([200, common_response_headers, body])
            backend.get_latest_job(id, params[:tube], params['timeout']) {|job|
              body.succeed_with(:id => job.id, :body => job.body)
            }.on_error {|message|
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
      EM.run do
        Thin::Server.start(web_host, web_port, builder.to_app)
      end      
    end
  end
end



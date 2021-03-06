require 'snap_search'
require 'rack/snap_search/config'

module Rack
    
    # Use to enable SnapSearch detection within your web application.
    class SnapSearch
        
        # Initialize the middleware.
        # 
        # @param [#call] app The Rack application.
        # @param [Hash, #to_h] options Options to configure this middleware with.
        # @yield [Rack::SnapSearch::Config, SnapSearch::Detector] A block to further modify the middleware.
        # @yieldparam [Rack::SnapSearch::Config] config Options to configure this middleware with, optionally preset with the `options` param.
        # @yieldparam [SnapSearch::Detector] detector The instance of the Detector class which will be used for detecting whether requests are coming from a robot.
        def initialize(app, options={}, &block)
            raise TypeError, 'app must respond to #call' unless app.respond_to?(:call)
            raise TypeError, 'options must be a Hash or respond to #to_h or #to_hash' unless options.is_a?(Hash) || options.respond_to?(:to_h)    || options.respond_to?(:to_hash)
            options = options.to_h rescue options.to_hash
            
            @app, @config = app, Rack::SnapSearch::Config.new(options)
            @config.x_forwarded_proto ||= true
            
            detector = ::SnapSearch::Detector.new
            
            block.call(@config, detector) if block_given?
            
            client = ::SnapSearch::Client.new( email: @config.email, key: @config.key )
            @interceptor = ::SnapSearch::Interceptor.new(client, detector)
        end
        
        # Run the middleware.
        # 
        # @param [Hash, to_h] app The Rack environment
        def call(environment)
            raise TypeError, 'environment must be a Hash or respond to #to_h or #to_hash' unless environment.is_a?(Hash) || environment.respond_to?(:to_h)    || environment.respond_to?(:to_hash)
            environment = environment.to_h rescue environment.to_hash
            
            # Check X-Forwarded-Proto because Heroku SSL Support terminates at the load balancer
            if @config.x_forwarded_proto && environment['X-FORWARDED-PROTO']
                environment['HTTPS'] = true && environment['rack.url_scheme'] = 'https' && environment['SERVER_PORT'] = 443 if environment['X-FORWARDED-PROTO'] == 'https'
                environment['HTTPS'] = false && environment['rack.url_scheme'] = 'http' && environment['SERVER_PORT'] = 80 if env['X-FORWARDED-PROTO'] == 'http'
            end
            
            @status, @headers, @body = @app.call(environment)
            @request = Rack::Request.new(environment.to_h)
            
            setup_response
            setup_attributes if @response
            
            [ @status, @headers, @body ]
        end
        
        protected
        
        # Intercept and return the response.
        def setup_response
            begin
                @response = @interceptor.intercept(request: @request) # TODO: ignored_routes, matched_routes, robots_json, & check_static_files options
            rescue SnapSearch::Exception => exception
                @config.on_exception.nil? ? raise(exception) : @config.on_exception.call(exception)
            end
        end
        
        # Setup the Location header in the response.
        def setup_location_header
            response_location_header = @response.headers.find { |header| header['name'] == 'Location' }
            
            @headers['Location'] = response_location_header['value'] unless response_location_header.nil?
        end
        
        # Setup the Status header and body in the response.
        def setup_status_and_body
            @status, @body = @response.status, @response.body # TODO: Need to status.to_i?
        end
        
        # Setup Location and Status headers, as well as teh body, if we got a response from SnapSearch.
        def setup_attributes
            setup_location_header
            # TODO: Should setup_content_length_header?
            setup_status_and_body
        end
        
    end
    
end

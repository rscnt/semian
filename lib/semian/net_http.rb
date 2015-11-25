require 'semian'
require 'semian/adapter'

module Net
  ProtocolError.include(::Semian::AdapterError)

  class SemianError < ::Net::ProtocolError
    def initialize(semian_identifier, *args)
      super(*args)
      @semian_identifier = semian_identifier
    end
  end

  ResourceBusyError = Class.new(SemianError)
  CircuitOpenError = Class.new(SemianError)
end

module Semian
  module NetHTTP
    include Semian::Adapter

    ResourceBusyError = ::Net::ResourceBusyError
    CircuitOpenError = ::Net::CircuitOpenError

    def semian_configuration
      Semian::NetHTTP.retrieve_semian_configuration(address, port)
    end

    def semian_identifier
      "nethttp_#{semian_configuration[:name]}"
    end

    DEFAULT_ERRORS = [
      ::Timeout::Error, # includes ::Net::ReadTimeout and ::Net::OpenTimeout
      ::TimeoutError, # alias for above
      ::SocketError,
      ::Net::HTTPBadResponse,
      ::Net::HTTPHeaderSyntaxError,
      ::Net::ProtocolError,
      ::EOFError,
      ::IOError,
      ::SystemCallError, # includes ::Errno::EINVAL, ::Errno::ECONNRESET, ::Errno::ECONNREFUSED, ::Errno::ETIMEDOUT, and more
    ].freeze # Net::HTTP can throw many different errors, this tries to capture most of them

    # The naked methods are exposed as `raw_query` and `raw_connect` for instrumentation purpose
    def self.included(base)
      base.send(:alias_method, :raw_request, :request)
      base.send(:remove_method, :request)

      base.send(:alias_method, :raw_connect, :connect)
      base.send(:remove_method, :connect)
    end

    class << self
      attr_accessor :semian_configuration
      attr_accessor :exceptions

      def retrieve_semian_configuration(host, port)
        @semian_configuration.call(host, port) if @semian_configuration.respond_to?(:call)
      end

      def reset_exceptions
        self.exceptions = Semian::NetHTTP::DEFAULT_ERRORS.dup
      end
    end

    Semian::NetHTTP.reset_exceptions

    def raw_semian_options
      options = semian_configuration
      options = options.dup unless options.nil?
      options
    end

    def resource_exceptions
      Semian::NetHTTP.exceptions
    end

    def disabled?
      semian_configuration.nil?
    end

    def connect
      return raw_connect if disabled?
      acquire_semian_resource(adapter: :http, scope: :connection) { raw_connect }
    end

    def request(req, body = nil, &block)
      return raw_request(req, body, &block) if disabled?
      acquire_semian_resource(adapter: :http, scope: :query) { raw_request(req, body, &block) }
    end
  end
end

Net::HTTP.include(Semian::NetHTTP)

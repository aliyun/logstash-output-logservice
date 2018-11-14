# encoding: utf-8
require "logstash/outputs/base"
require "logstash/namespace"
require "logstash/environment"
require "stud/buffer"
require 'socket'
require "java"

import "java.util.ArrayList"

root_dir = File.expand_path(File.join(File.dirname(__FILE__), ".."))

LogStash::Environment.load_runtime_jars! File.join(root_dir, "vendor")

class LogStash::Outputs::LogService < LogStash::Outputs::Base
  include Stud::Buffer

  config_name "logservice"

  # log service config, https://help.aliyun.com/document_detail/sls/api/endpoints.html
  config :endpoint, :validate => :string, :required => true
  config :project, :validate=> :string, :required=> true
  config :logstore, :validate=> :string, :required=> true
  config :topic, :validate=> :string, :required=> false, :default=> ""
  # if source is null, will set ip default
  config :source, :validate=> :string, :required=> true

  # access_key_id/access_key_secret created by account of aliyun.com
  config :access_key_id, :validate=> :string, :required=> true
  config :access_key_secret, :validate=> :string, :required=> true

  # default 4000 logs in a logGroup for batch send
  config :max_buffer_items, :validate=> :number, :required=> false, :default=> 4000
  # default 2*1024*1024 Bytes in a logGroup for batch send
  config :max_buffer_bytes, :validate=> :number, :required=> false, :default=> 2097152
  # for batch send, logGroup will emit in default 3 seconds
  config :max_buffer_seconds, :validate=> :number, :required=> false, :default=> 3

  # logGroup will retry send to log service when error happened, and will be discard when retry times exceed limit
  config :max_send_retry, :validate=> :number, :required=> true, :default=> 10 
  # sleep default 200 milliseconds before retry next send
  config :send_retry_interval, :validate=> :number, :required=> false, :default=> 200

  Log = com.aliyun.openservices.log
  LogException = com.aliyun.openservices.log.exception.LogException
  LogCommon = com.aliyun.openservices.log.common

  public
  def register
    buffer_initialize(
        :max_items => @max_buffer_items,
        :max_interval => @max_buffer_seconds,
        :logger => @logger
    )
    @logclient = Log.Client::new(@endpoint, @access_key_id, @access_key_secret)
    if @source == ''
        @source = Socket.ip_address_list.detect{|intf| intf.ipv4_private?}.ip_address
    end
    @send_retry_interval_seconds = @send_retry_interval / 1000.0
    @logger.info("init logstash-output-logservice plugin", :endpoint => @endpoint, :project => @project, :logstore => @logstore, :topic => @topic, :source => @source, :max_buffer_bytes => @max_buffer_bytes)
  end # def register

  public
  def receive(event)
    return unless output?(event)
    begin
      buffer_receive(event)
    rescue => e
      @logger.warn("error encoding event for logstash-output-logservice", :exception => e, :event => event)
    end
  end # def event

  def send_to_log_service(loggroup)
    @retry = 0
    begin
      @retry += 1
      @logclient.PutLogs(@project, @logstore, @topic, loggroup, @source.to_s)
      @logger.info("send logs to logservice success", :logcount => loggroup.size().to_s)
    rescue LogException => e
      @error_code = e.GetErrorCode()
      @error_message = e.GetErrorMessage()
      if @retry < @max_send_retry
        @logger.warn("send logs to logservice fail, will retry later", :exception => e, :error_code => @error_code, :error_message => @error_message, :retry => @retry)
        sleep(@send_retry_interval_seconds)
        retry
      else
        @logger.error("send logs to logservice fail, discard data", :exception => e, :error_code => @error_code, :error_message => @error_message, :retry => @retry)
      end
    rescue => e
      if @retry < @max_send_retry
        @logger.warn("send logs to logservice fail, retry later", :exception => e, :retry => @retry)
        sleep(@send_retry_interval_seconds)
        retry
      else
        @logger.error("send logs to logservice fail, discard data", :exception => e, :retry => @retry)
      end
    end
  end

  # called from Stud::Buffer#buffer_flush when there are events to flush
  def flush(events, close=false)
    if events.size < 1
      return
    end

    @loggroup = ArrayList.new
    @byte_size = 0
    events.each { |x|
      begin
        @event_map = x.to_hash
        if @event_map.size < 1
          next
        end
        @logitem = LogCommon.LogItem.new
        #@timestamp like 2016-02-18T03:23:11.053Z
        @logitem.SetTime(Time.parse(@event_map['@timestamp'].to_s).to_i)
        @event_map.each do | key, value |
          @key_str = key.to_s
          @value_str = value.to_s
          @byte_size += @key_str.length + @value_str.length
          @logitem.PushBack(@key_str, @value_str)
        end
        @loggroup.add(@logitem)
        if @byte_size > @max_buffer_bytes
          send_to_log_service(@loggroup)
          @loggroup = ArrayList.new
          @byte_size = 0
        end
      rescue => e
        @logger.warn("deserialize log data from json to LogGroup(protobuf) fail", :exception => e)
      end
    }
    if @byte_size > 0
      send_to_log_service(@loggroup)
    end
  end

  public
  def close
    buffer_flush(:final => true)
  end # def close

end # class LogStash::Outputs::LogService

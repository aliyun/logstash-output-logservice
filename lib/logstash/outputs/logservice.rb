# encoding: utf-8
require "logstash/outputs/base"
require "logstash/namespace"
require "logstash/environment"
require "stud/buffer"
require 'socket'
require "java"
require 'json'

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
  config :max_buffer_items, :validate=> :number, :required=> false, :default=> 4096
  # default 2*1024*1024 Bytes in a logGroup for batch send
  config :max_buffer_bytes, :validate=> :number, :required=> false, :default=> 2097152
  # for batch send, logGroup will emit in default 3 seconds
  config :max_buffer_seconds, :validate=> :number, :required=> false, :default=> 3
  # the maximum log size that a single producer instance can cache is 100MB by default.
  config :total_size_in_bytes, :validate=> :number, :required=> false, :default=> 104857600

  # logGroup will retry send to log service when error happened, and will be discard when retry times exceed limit
  config :max_send_retry, :validate=> :number, :required=> true, :default=> 10
  # sleep default 200 milliseconds before retry next send
  config :send_retry_interval, :validate=> :number, :required=> false, :default=> 200

  config :to_json, :validate=> :boolean, :required=> false, :default=> true
  config :time_key, :validate=> :string, :required=> false, :default=> "@timestamp"

  LP = com.aliyun.openservices.aliyun.log.producer
  LogCommon = com.shade.aliyun.openservices.log.common


  public
  def register
    @producerConfig = LP.ProducerConfig::new();
    @producerConfig.setBatchCountThreshold(@max_buffer_items);
    @producerConfig.setBatchSizeThresholdInBytes(@max_buffer_bytes);
    @producerConfig.setLingerMs(@max_buffer_seconds*1000);
    @producerConfig.setRetries(@max_send_retry);
    @producerConfig.setBaseRetryBackoffMs(@send_retry_interval);
    @producerConfig.setTotalSizeInBytes(@total_size_in_bytes);
    @producer = LP.LogProducer::new(@producerConfig);
    @producer.putProjectConfig(LP.ProjectConfig::new(@project, @endpoint, @access_key_id,  @access_key_secret));

    @logger.info("init logstash-output-logservice plugin", :endpoint => @endpoint, :project => @project, :logstore => @logstore, :topic => @topic, :source => @source, :max_buffer_bytes => @max_buffer_bytes)
  end # def register

  public
  def receive(event)
    begin
      @event_map = event.to_hash
      if @event_map.size < 1
        return
      end
      @logitem = LogCommon.LogItem.new
      #@timestamp like 2016-02-18T03:23:11.053Z
      time_value = @event_map[@time_key]
      if time_value.nil?
         time_value = @event_map['@timestamp']
         @logger.warn("The time_key is nil, use @timestamp")
      end
      @logitem.SetTime(Time.parse(time_value.to_s).to_i)
      @event_map.each do | key, value |
        @key_str = key.to_s
        if @key_str == '__time__'
          next
        end
        if value.instance_of? Hash
          @value_str = value.to_json
        else
          @value_str = value.to_s
        end
        @logitem.PushBack(@key_str, @value_str)
      end
      @producer.send(@project, @logstore, @topic, @source, @logitem)
      rescue => e
        @logger.warn("send log data fail", :exception => e)
      end
    end # def event

  def flush(events, close=false)
  end

  public
  def close
    @producer.close();
  end # def close

end # class LogStash::Outputs::LogService
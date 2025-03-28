# Logstash 日志服务 Output 插件

本插件作为[Logstash](https://github.com/elastic/logstash)的output插件，提供输出日志到日志服务的功能。

* RubyGems: [logstash-output-logservice](https://rubygems.org/gems/logstash-output-logservice)

## 安装步骤

1. 将插件添加到Logstash中:
```sh
logstash-plugin install logstash-output-logservice
```
2. 查看安装的插件及其版本：
```sh
logstash-plugin list --verbose logstash-output-logservice
```  

## 配置示例

其中前7个参数 `endpoint` 到 `max_send_retry` 为必填项

其他参数为选填项

```
output {
  logservice {
      endpoint => "your project endpoint"
      project => "your project name"
      logstore => "your logstore name"
      access_key_id => "your access id"
      access_key_secret => "your access key"
      source  => "" 
      max_send_retry  => 10
      topic => "" 
      max_buffer_items => 4096
      max_buffer_bytes => 2097152
      max_buffer_seconds => 3
      total_size_in_bytes => 104857600
      send_retry_interval => 200
      time_key => "@timestamp"
   }
}  
```

## 配置说明

|参数名|  参数类型  | 是否必填 | 备注                            |
|:---:|:------:|:----:|:------------------------------|
|endpoint| string |  是   | 日志服务项目所在的endpoint             |
|project| string |  是   | 日志服务项目名                       |
|logstore| string |  是   | 日志服务日志库名                      |
|access_id| string |  是   | 阿里云Access Key ID              |
|access_key| string |  是   | 阿里云Access Key Secret          |
|source| string |  是   | 上传日志中的source字段                |
|max_send_retry| number |  是   | 上传失败重试次数                      |
|topic| string |  否   | 上传日志中的topic字段,默认为""           |
|max_buffer_items| number |  否   | 发送缓存日志条数上限,默认为4096            |
|max_buffer_bytes| number |  否   | 发送缓存日志字节数上限,默认为2097152  (2MB) |
|max_buffer_seconds| number |  否   | 发送缓存日志时间上限,默认为3秒              |
|total_size_in_bytes| number |  否   | 缓存日志总字节数上限,默认为104857600  (100MB) |
|send_retry_interval| number |  否   | 上传失败重试间隔,默认为200毫秒             |
|time_key| string |  否   | 上传日志中的时间戳字段,默认为"@timestamp"   |

## 开发参考

```sh
#代码编译
gem build logstash-output-logservice.gemspec
#发布
gem push logstash-output-logservice-VERSION.gem
#生成离线包
logstash-plugin prepare-offline-pack logstash-output-logservice
```

## 常见问题

1. **插件安装失败**  
   由于网络问题，导致无法连接到默认的 RubyGems 源。
   - 配置国内镜像源，如[Ruby China](https://index.ruby-china.com)  
     
2. **权限配置**
   - 参考[RAM自定义授权示例](https://help.aliyun.com/zh/sls/use-custom-policies-to-grant-permissions-to-a-ram-user)，确保插件有日志服务日志库的写入权限

3. **日志上传失败**
   - 根据Logstash运行日志具体分析
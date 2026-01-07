#!/bin/bash
# 需要根据实际ES集群环境替换
es_user="elastic"
es_pw="$2"
es_address="${1}"
 
curl -XPUT -u ${es_user}:${es_pw} ${es_address}/_template/qtevent?pretty -H 'Content-Type:application/json' -d'
{
  "index_patterns": [
    "qtevent*"
  ],
  "mappings": {
    "dynamic_templates": [
      {
        "strings": {
          "mapping": {
            "analyzer": "ik_max_word",
            "fields": {
              "keyword": {
                "ignore_above": 8191,
                "type": "keyword"
              }
            },
            "norms": false,
            "search_analyzer": "ik_smart",
            "type": "text"
          },
          "match_mapping_type": "string"
        }
      }
    ],
    "properties": {
      "agent_id": {
        "type": "keyword"
      },
      "agent_ip": {
        "ignore_malformed": "true",
        "type": "ip"
      },
      "comid": {
        "type": "keyword"
      },
      "datatime": {
        "format": "strict_date_optional_time || epoch_second",
        "type": "date"
      },
      "datatype": {
        "type": "keyword"
      },
      "external_ip": {
        "ignore_malformed": "true",
        "type": "ip"
      },
      "group": {
        "type": "integer"
      },
      "id": {
        "type": "keyword"
      },
      "internal_ip": {
        "ignore_malformed": "true",
        "type": "ip"
      },
      "os": {
        "type": "keyword"
      },
      "processed_time": {
        "format": "epoch_second",
        "ignore_malformed": "true",
        "type": "date"
      },
      "severity": {
        "type": "keyword"
      },
      "type": {
        "type": "keyword"
      },
      "host_memo": {
        "type": "keyword"
      },
      "host_tag": {
        "type": "keyword"
      },
      "host_name": {
        "type": "keyword"
      },
      "group_name": {
        "type": "keyword"
      },
      "action": {
        "type": "keyword"
      }
    }
  },
  "order": 0,
  "settings": {
    "index.indexing.slowlog.level": "info",
    "index.indexing.slowlog.threshold.index.info": "5s",
    "index.indexing.slowlog.threshold.index.warn": "10s",
    "index.lifecycle.name": "v6_ilm",
    "index.merge.policy.max_merged_segment": "2gb",
    "index.merge.policy.segments_per_tier": "24",
    "index.number_of_replicas": "1",
    "index.refresh_interval": "30s",
    "index.routing.allocation.total_shards_per_node": "-1",
    "index.search.slowlog.level": "info",
    "index.search.slowlog.threshold.fetch.info": "800ms",
    "index.search.slowlog.threshold.fetch.warn": "1s",
    "index.search.slowlog.threshold.query.info": "5s",
    "index.search.slowlog.threshold.query.warn": "10s",
    "index.sort.field": [
      "datatime"
    ],
    "index.sort.order": [
      "desc"
    ],
    "index.translog.durability": "async",
    "index.translog.flush_threshold_size": "2gb",
    "index.translog.sync_interval": "120s",
    "index.unassigned.node_left.delayed_timeout": "5d",
    "index.number_of_shards": "1"
  }
}'
 
curl -XPUT -u ${es_user}:${es_pw} ${es_address}/_template/dns_access?pretty -H 'Content-Type:application/json' -d'
{
  "index_patterns": [
    "*dns_access*"
  ],
  "mappings": {
    "properties": {
      "pid": {
        "type": "long"
      }
    }
  },
  "order": 1
}'
 
curl -XPUT -u ${es_user}:${es_pw} ${es_address}/_template/net_connect?pretty -H 'Content-Type:application/json' -d'
{
  "index_patterns": [
    "*net_connect*"
  ],
  "mappings": {
    "properties": {
      "dst_ip": {
        "ignore_malformed": "true",
        "type": "ip"
      },
      "dst_port": {
        "type": "integer"
      },
      "ip_type": {
        "type": "keyword"
      },
      "log_type": {
        "type": "keyword"
      },
      "pid": {
        "type": "long"
      },
      "ppid": {
        "type": "long"
      },
      "ppuid": {
        "type": "long"
      },
      "src_ip": {
        "ignore_malformed": "true",
        "type": "ip"
      },
      "src_port": {
        "type": "integer"
      },
      "status": {
        "type": "keyword"
      },
      "uid": {
        "type": "long"
      },
      "proto": {
        "type": "keyword"
      }
    }
  },
  "order": 1,
  "settings": {
    "index.routing.allocation.total_shards_per_node": "-1",
    "index.number_of_shards": "1"
  }
}'
 
curl -XPUT -u ${es_user}:${es_pw} ${es_address}/_template/proc_create?pretty -H 'Content-Type:application/json' -d'
{
  "index_patterns": [
    "*proc_create*"
  ],
  "mappings": {
    "properties": {
      "euid": {
        "type": "long"
      },
      "pid": {
        "type": "long"
      },
      "ppid": {
        "type": "long"
      },
      "ppuid": {
        "type": "long"
      },
      "uid": {
        "type": "integer"
      },
      "ppmd5": {
        "type": "keyword"
      },
      "ppsha1": {
        "type": "keyword"
      },
      "sha1": {
        "type": "keyword"
      },
      "md5": {
        "type": "keyword"
      },
      "ppsha256": {
        "type": "keyword"
      }
    }
  },
  "order": 1,
  "settings": {
    "index.routing.allocation.total_shards_per_node": "-1",
    "index.number_of_shards": "1"
  }
}'
 
curl -XPUT -u ${es_user}:${es_pw} ${es_address}/_template/access_log?pretty -H 'Content-Type:application/json' -d'
{
  "index_patterns": [
    "*access_log*"
  ],
  "mappings": {
    "properties": {
      "log_type": {
        "type": "keyword"
      },
      "login_con_port": {
        "type": "integer"
      },
      "login_err_reason": {
        "type": "keyword"
      },
      "pid": {
        "type": "long"
      },
      "port": {
        "type": "integer"
      },
      "src_ip": {
        "ignore_malformed": "true",
        "type": "ip"
      }
    }
  },
  "order": 1
}'
 
curl -XPUT -u ${es_user}:${es_pw} ${es_address}/_template/account_change?pretty -H 'Content-Type:application/json' -d'
{
  "index_patterns": [
    "*account_change*"
  ],
  "mappings": {
    "properties": {
      "gid": {
        "type": "long"
      },
      "pre_gid": {
        "type": "long"
      },
      "pre_uid": {
        "type": "long"
      },
      "uid": {
        "type": "long"
      },
      "pre_login_shell": {
        "type": "keyword"
      },
      "shell": {
        "type": "keyword"
      },
      "sudo_shell": {
        "type": "keyword"
      },
      "gname": {
        "type": "keyword"
      },
      "pre_home": {
        "type": "keyword"
      },
      "pre_gname": {
        "type": "keyword"
      },
      "category": {
        "type": "keyword"
      },
      "uname": {
        "type": "keyword"
      },
      "home": {
        "type": "keyword"
      },
      "pre_sudo_shell": {
        "type": "keyword"
      },
      "cur_value": {
        "type": "keyword"
      },
      "pre_sudo_name": {
        "type": "keyword"
      },
      "sudo_uname": {
        "type": "keyword"
      },
      "pre_uname": {
        "type": "keyword"
      },
      "pre_value": {
        "type": "keyword"
      }
    }
  },
  "order": 1
}'
 
curl -XPUT -u ${es_user}:${es_pw} ${es_address}/_template/shell_log?pretty -H 'Content-Type:application/json' -d'
{
  "index_patterns": [
    "*shell_log*"
  ],
  "mappings": {
    "properties": {
      "euid": {
        "type": "long"
      },
      "pid": {
        "type": "long"
      },
      "src_ip": {
        "ignore_malformed": "true",
        "type": "ip"
      },
      "uid": {
        "type": "long"
      },
      "iam_user": {
        "type": "keyword"
      },
      "iam_ip": {
        "type": "keyword"
      },
      "iam_name": {
        "type": "keyword"
      },
      "tty": {
        "type": "keyword"
      }
    }
  },
  "order": 1
}'
application:
  #模式 debug test release， release模式不开启swagger
  mode: release
  # 服务器ip，默认使用 0.0.0.0
  host: 0.0.0.0
  # 服务名称
  name: go-patrol
  # 端口号
  port: "{{.Env.patrol_port}}" # 服务端口号
  referCheck: true
  referers: "http://localhost:{{.Env.patrol_port}},https://localhost:{{.Env.patrol_port}},http://{{.Env.web_publicip}}:{{.Env.patrol_port}},https://{{.Env.web_publicip}}:{{.Env.patrol_port}}{{ if .Env.web_domain }},http://{{.Env.web_domain}}:{{.Env.patrol_port}},https://{{.Env.web_domain}}:{{.Env.patrol_port}}{{ end }}{{ if .Env.web_ipv6 }},http://{{.Env.web_ipv6}}:{{.Env.patrol_port}},https://{{.Env.web_ipv6}}:{{.Env.patrol_port}}{{ end }}"
  readtimeout: 1
  writertimeout: 2
  sqliteDbFile: /data/app/titan-go-patrol/db/db.sqlite
  mysqlConfig:
    username: root
    addr: mysql
  certFile: /data/app/titan-go-patrol/config/cert/server.pem
  keyFile: /data/app/titan-go-patrol/config/cert/key.pem
  workDir: /data/app/titan-go-patrol/compose/
  signPublicKey: MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDYuURg9ZWeTKpdQMbR0MIB4yLk+7yz+OVlrwOzDApRmxxXIxfRNouvjElugmwbofACNIEvkP3y2P8IAIyrW4LJsp1ltbliEVhmmusOklR9vPOGsn4BeC8S2RFgtGbnmgxV3hgW+7NWehsYnO3ryTgTrvM0yAqlA2EhAhd5z+E81QIDAQAB
  extParams:
    docker_enable: "{{default "false" .Env.docker_enable}}"
    bigdata_enable: "{{default "false" .Env.bigdata_enable}}"
    thp_enable: "{{default "false" .Env.thp_enable}}"
logger:
  # 日志存放路径
  path: /data/titan-logs/go/patrol/
  # 日志等级
  level: info
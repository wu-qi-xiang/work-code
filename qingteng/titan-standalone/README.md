# standalone-base
## 用于构建titan-base
自动化打包el6 el7 base包

== 会自动打包的分支格式为master-base-v${version}/master-base-v${version}-test ==

> 关注 gitlab-ci.yml workflow 部分控制

在符合分支名称规范的分支前提下，

对应版本的-test分支用于构建test包;

同上，分支不是以-test结尾的分支会自动构建release包。

release分支请填写对应的patch base分支 basic_version

初始化的分支需要更新.gitlab-ci.yml文件相关参数

```
variables:
  #包版本
  vesion: "v3.4.0.11"
  #基准包版本
  basic_version: "v3.4.0.11"

version 构建打包的版本,必须填
basic_version 基准包版本,必须填,无论test包还是release包都需要填写，
test包构建逻辑还是会以自己对应的版本作为基准包,所以构建逻辑会自动设置为空。
```

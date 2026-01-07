#!/bin/bash

readonly R_COLOR_G="\x1b[0;32m"
readonly R_COLOR_R="\x1b[1;31m"
readonly R_COLOR_Y="\x1b[1;33m"
readonly R_RESET="\x1b[0m"
readonly R_LARK_BASEURL="https://open.feishu.cn"
readonly R_LARK_API_BASEURL="$R_LARK_BASEURL/open-apis"
readonly R_TOOL_NAME="lark-cli"

# shellcheck disable=SC2034
readonly R_PARAM_APP_ID_DESCRIPTION="应用的appID，当使用应用机器人发送消息的时候必须指定该参数"
# shellcheck disable=SC2034
readonly R_PARAM_APP_SECRET_DESCRIPTION="应用的appSecret，当使用应用机器人发送消息的时候必须指定该参数"
# shellcheck disable=SC2034
readonly R_PARAM_EMAILS_DESCRIPTION="以邮箱来指定飞书消息的接收人, 可以是多个, 以英文的逗号隔开, 例如: \"xxx@xx.cn,yy@yy.cn\"。当使用应用机器人发送消息的时候必须指定该参数"
# shellcheck disable=SC2034
readonly R_PARAM_ID_TYPE_DESCRIPTION="获取的id类型，取值范围为：open_id或user_id，如果不指定，则默认打印：<email> <user_id> <open_id>"
# shellcheck disable=SC2034
readonly R_PARAM_MSG_DESCRIPTION="待发送的消息或消息模板文件路径, 消息字符串具体格式请参考: https://open.feishu.cn/document/uAjLw4CM/ukTMukTMukTM/reference/im-v1/message。"
# shellcheck disable=SC2034
readonly R_PARAM_WEBHOOK_DESCRIPTION="自定义机器人webhook地址，当使用自定义机器人发送消息的时候必须指定该参数"

## 一般日志打印
info_log() {
  echo -e "${R_COLOR_G}[info]$*${R_RESET}"
}
## 错误日志打印
error_log() {
  echo -e "${R_COLOR_R}[error]$*${R_RESET}" >&2
  exit 1
}
## 警告日志打印
warn_log() {
  echo -e "${R_COLOR_Y}[warn]$*${R_RESET}"
}

## 获取变量
# $1: Var Name, 变量名称
get_var() {
  local var_name="$1"
  [ -z "$var_name" ] && return
  eval echo \"'$'"${var_name}"\"
}

## 拼接字符串，例如：TEST-1234,PM-1025
# $1 左边字符串
# $2 右边字符串
# $3 拼接符号，默认逗号
append() {
  local left_string="$1"
  local right_string="$2"
  local append_symbol="$3"
  [[ -z $append_symbol ]] && append_symbol=","
  if [[ -n $left_string ]]; then
    left_string="$left_string$append_symbol$right_string"
  else
    left_string="$right_string"
  fi
  echo -n "$left_string"
}

## 检查环境
# $1: 要检查的命令, 以空格隔开, 例如:check_command "jq" "tar"
check_command() {
  local to_checks=("$@")
  local cmd
  local not_found_cmd=""
  for cmd in "${to_checks[@]}"; do
    command -v "${cmd}" > /dev/null 2>&1 || not_found_cmd=$(append "${not_found_cmd}" "${cmd}" "、")
  done
  [[ -n "${not_found_cmd}" ]] && error_log "${not_found_cmd}命令不存在, 请自行安装."
}

## 使用eval创建动态的变量, 仅适用于简单变量
# : 变量名称
# : 变量值
create_dynamic_var() {
  local name="$1"
  local value="$2"
  # 需要将"-"转换成"_"
  # 在变量名称前加上前缀v_，因为有的name可能是数字，可能会有不符合规范的变量命名
  name="v_${name//-/_}"
  eval "$name=$value"
}
## 获取简单变量
# : 变量名称
get_dynamic_var() {
  local name="$1"
  # 需要将"-"转换成"_"
  # 在变量名称前加上前缀v_，因为有的name可能是数字，可能会有不符合规范的变量命名
  name="v_${name//-/_}"
  get_var "$name"
}

## 解释Action
# $1: Action
# $2: Description
# $3: Use Example
explain_action() {
  local -r indent="25"
  local action="$1"
  local description="$2"
  local use_example="$3"
  if [ -n "$use_example" ]; then
    printf "  %-${indent}s %s\n   %${indent}s示例: %s\n\n"  "$action" "$description" "" "$use_example"
  else
    printf "  %-${indent}s %s\n\n"  "$action" "$description"
  fi
}

## 解释某个Action(带参数的描述)
# $1: Action
# $2: Param
# $3: Description
# $4: Value Example
explain_action_with_param() {
  local -r indent="25"
  local action="$1"
  local params=("${@:2}")
  local var_name
  printf "%s %s\n\n" "$R_TOOL_NAME" "$action"
  printf "%s\n" "requires:"
  for param in "${params[@]}"; do
    var_name="R_PARAM_$(echo "${param^^}" | tr '-' '_')_DESCRIPTION"
    printf "  %-${indent}s %s\n" "--$param" "$(get_var "$var_name")"
  done
  if [ -z "$options_str" ]; then
    return
  fi
  echo
  IFS=" " read -r -a option_params_arr <<< "$options_str"
  printf "%s\n" "options:"
  for option_param in "${option_params_arr[@]}"; do
    var_name="R_PARAM_$(echo "${option_param^^}" | tr '-' '_')_DESCRIPTION"
    printf "  %-${indent}s %s\n" "--$option_param" "$(get_var "$var_name")"
  done
}

## 检查Action所需要的param
# $1: Action
# $2...$n: Required Param
check_action_param() {
  local action="$1"
  local to_checks=("${@:2}")
  if [ " -h -- '${action}'" == "$parameters" ] || [ " --help -- '${action}'" == "$parameters" ]; then
    explain_action_with_param "$action" "${to_checks[@]}"
    exit 0
  fi
  local param
  local required_param=""
  for param in "${to_checks[@]}"; do
    echo "$parameters" | grep "'$action'" | grep -v "\-\-$param" > /dev/null && required_param=$(append "${required_param}" "--${param}")
  done
  [[ -n "${required_param}" ]] && error_log "Action '$action' requires ${required_param} param."
}

action_params_check_get_id() {
  options_str=""
  check_action_param get-id app-id app-secret emails
}

action_params_check_send_msg() {
  options_str="app-id app-secret emails webhook"
  check_action_param send-msg msg
}

## 获取Access Token, token的值被设置在<access_token>变量中
# $1: APP ID
# $2: APP Secret
get_access_token() {
  local -r app_id="$1"
  [[ -z "$app_id" ]] && error_log "app-id不允许为空."
  local -r app_secret="$2"
  [[ -z "$app_secret" ]] && error_log "app-secret不允许为空."
  local -r res=$(curl --location --request POST -s -w "\n%{http_code}" \
    "${R_LARK_API_BASEURL}/auth/v3/tenant_access_token/internal/" \
    --header "Content-Type: application/json" \
    --data "{\"app_id\":\"$app_id\",\"app_secret\":\"$app_secret\"}")
  local -r res_ret_code=$(echo "$res" | tail -1)
  local -r res_ret_body=$(echo "$res" | head -1)
  local -r error_msg="获取Access Token失败. app_id: ${app_id}. response code: ${res_ret_code}, body: ${res_ret_body}"
  [[ $res_ret_code != 200 ]] && error_log "$error_msg"
  local -r code=$(echo "$res_ret_body" | jq -r .code)
  [[ $code != 0 ]] && error_log "$error_msg"
  access_token=$(echo "$res_ret_body" | jq -r .tenant_access_token)
}

## 根据邮箱获取飞书用户的user_id, user_id的值被设置在一个动态变量中, 例如:
## 邮箱ji.chen@qingteng.cn对应的user_id被设置在ji_chen_qingteng_cn_user_id变量中, 可以使用get_user_id_dynamic_var方法直接获取值
# $1: Access Token
# $2: Emails, 以逗号分割, 例如: xxx@xx.cn,yy@yy.cn
get_user_id() {
  local -r access_token="$1"
  [[ -z "$access_token" ]] && error_log "access_token不允许为空."
  local -r emails="$2"
  [[ -z "$emails" ]] && error_log "email不允许为空."

  local request_param=""
  IFS="," read -r -a email_arr <<< "$emails"
  for email in "${email_arr[@]}"; do
    request_param=$(append "$request_param" "emails=${email}" "&")
  done

  local -r res=$(curl --location --request GET -s -w "\n%{http_code}" \
    "${R_LARK_API_BASEURL}/user/v1/batch_get_id?${request_param}" \
    --header "Authorization: Bearer ${access_token}")
  local -r res_ret_code=$(echo "$res" | tail -1)
  local -r res_ret_body=$(echo "$res" | head -1)
  local -r error_msg="获取用户ID失败. emails: ${emails}. response code: ${res_ret_code}, body: ${res_ret_body}"
  [[ $res_ret_code != 200 ]] && error_log "$error_msg"
  local -r code=$(echo "$res_ret_body" | jq -r .code)
  [[ $code != 0 ]] && error_log "$error_msg"
  local -r email_users=$(echo "$res_ret_body" | jq -r .data.email_users)
  local user_id_exists
  local open_id_exists
  for email in "${email_arr[@]}"; do
    user_id_exists=$(echo "$email_users" | jq -r ".\"${email}\"[0].user_id")
    [ "$user_id_exists" == "null" ] && continue
    create_user_id_dynamic_var "$email" "$user_id_exists"

    open_id_exists=$(echo "$email_users" | jq -r ".\"${email}\"[0].open_id")
    [ "$open_id_exists" == "null" ] && continue
    create_open_id_dynamic_var "$email" "$open_id_exists"
  done
}

## 以应用机器人的身份发送飞书消息
# $1: Access Token
# $2: User ID
# $3: Msg
send_msg_by_user_id() {
  local -r access_token="$1"
  [[ -z "$access_token" ]] && error_log "access_token不允许为空."
  local -r user_id="$2"
  [[ -z "$user_id" ]] && error_log "user_id不允许为空."

  local request_data_file=""
  local msg_treated="$msg"
  local -r tmp_msg_file_name="/tmp/lark/$(date '+%s%N')"
  mkdir -p "/tmp/lark"
  if [ -f "$msg" ]; then
    request_data_file="@"
    # 模板消息处理，写到新的文件中
    envsubst < "$msg" > "$tmp_msg_file_name"
    msg_treated=$tmp_msg_file_name
  fi

  local -r res=$(curl --location --request POST -s -w "\n%{http_code}" \
    "${R_LARK_API_BASEURL}/message/v4/send/?user_id=${user_id}" \
    --header 'Content-Type: application/json' \
    --header "Authorization: Bearer ${access_token}" \
    --data "$request_data_file$msg_treated")
  rm -rf "$tmp_msg_file_name"

  local -r res_ret_code=$(echo "$res" | tail -1)
  local -r res_ret_body=$(echo "$res" | head -1)
  local -r error_msg="发送消息失败. email: ${email}. response code: ${res_ret_code}, body: ${res_ret_body}"
  [[ $res_ret_code != 200 ]] && error_log "$error_msg"
  local -r code=$(echo "$res_ret_body" | jq -r .code)
  [[ $code != 0 ]] && error_log "$error_msg"
  echo "$res_ret_body"
}

## 创建用户ID的动态变量
# $1: Email
# $2: Value
create_user_id_dynamic_var() {
  local -r email="$1"
  local -r value="$2"
  local -r name="${email//[@\.]/_}_user_id"
  create_dynamic_var "$name" "$value"
}
## 获取用户ID的动态变量
# $1: Email
get_user_id_dynamic_var() {
  local -r email="$1"
  local -r name="${email//[@\.]/_}_user_id"
  get_dynamic_var "$name"
}
## 创建用户OpenID的动态变量
# $1: Email
# $2: Value
create_open_id_dynamic_var() {
  local -r email="$1"
  local -r value="$2"
  local -r name="${email//[@\.]/_}_open_id"
  create_dynamic_var "$name" "$value"
}
## 获取用户OpenID的动态变量
# $1: Email
get_open_id_dynamic_var() {
  local -r email="$1"
  local -r name="${email//[@\.]/_}_open_id"
  get_dynamic_var "$name"
}

## 以自定义机器人的身份发送飞书消息
# $1: Webhook
send_msg_by_webhook() {
  local -r webhook="$1"
  [[ -z "$webhook" ]] && error_log "webhook不允许为空."

  local request_data_file=""
  local msg_treated="$msg"
  local -r tmp_msg_file_name="/tmp/lark/$(date '+%s%N')"
  mkdir -p "/tmp/lark"
  if [ -f "$msg" ]; then
    request_data_file="@"
    # 模板消息处理，写到新的文件中
    envsubst < "$msg" > "$tmp_msg_file_name"
    msg_treated=$tmp_msg_file_name
  fi

  local -r res=$(curl --location --request POST -s -w "\n%{http_code}" \
    "$webhook" \
    --header 'Content-Type: application/json' \
    --data "$request_data_file$msg_treated")
  rm -rf "$tmp_msg_file_name"

  local -r res_ret_code=$(echo "$res" | tail -1)
  local -r res_ret_body=$(echo "$res" | head -1)
  local -r error_msg="发送消息失败. email: ${email}. response code: ${res_ret_code}, body: ${res_ret_body}"
  [[ $res_ret_code != 200 ]] && error_log "$error_msg"
  # 这里稍微注意下一，自定义机器人的业务返回码字段是StatusCode，而不是code
  local -r code=$(echo "$res_ret_body" | jq -r .StatusCode)
  [[ $code != 0 ]] && error_log "$error_msg"
  echo "$res_ret_body"
}

action_get_id() {
  check_command "jq"
  get_access_token "$app_id" "$app_secret"
  get_user_id "$access_token" "$emails"

  local user_id
  local open_id
  if [ -n "$id_type" ]; then
    # 参数互斥校验
    [ ${#email_arr[@]} -gt 1 ] && error_log "The '--id-type' parameter is not allowed when multiple email are specified."
    if [ "$id_type" == "user_id" ]; then
      get_user_id_dynamic_var "$emails"
    elif [ "$id_type" == "open_id" ]; then
      get_open_id_dynamic_var "$email"
    else
      error_log "The id type is not supported, the supported ID types are 'open_id' and 'user_id'. ID type: ${id_type}".
    fi
    return
  fi
  for email in "${email_arr[@]}"; do
    user_id=$(get_user_id_dynamic_var "$email")
    open_id=$(get_open_id_dynamic_var "$email")
    echo "$email $user_id $open_id"
  done
}

action_send_msg() {
  check_command "jq" "envsubst"

  if [ -n "$webhook" ]; then
    # 以自定义机器人的身份发送消息
    send_msg_by_webhook "$webhook"
  else
    # 以应用机器人的身份发送消息
    IFS="," read -r -a email_arr <<< "$emails"
    get_access_token "$app_id" "$app_secret"
    get_user_id "$access_token" "$emails"
    local user_id
    for email in "${email_arr[@]}"; do
      user_id=$(get_user_id_dynamic_var "$email")
      send_msg_by_user_id "$access_token" "$user_id"
    done
  fi
}

action_help() {
  printf "%s\n  $R_TOOL_NAME\n\n" "名称:"
  printf "%s\n  %s\n\n" "版本:" "v1.0.0"
  printf "%s\n  %s\n\n" "Actions:" "help,get-id,send-msg"
  explain_action "get-id" "根据邮箱获取open_id和user_id" "./lark-cli.sh get-id --app-id=<app_id> --app-secret=<app_secret> --emails=<email>,<email>"
  explain_action "send-msg" "利用应用机器人或自定义机器人发送飞书消息，如果指定了webhook参数则表示使用自定义机器人发送消息，否则使用应用机器人发送消息" "./lark-cli.sh send-msg --app-id=<app_id> --app-secret=<app_secret> --emails=<email>,<email> --msg=<msg>"
}

## shell执行的核心部分
readonly R_LONG_OPTIONS="app-id::,app-secret::,emails::,id-type:,msg:,webhook::,help"
readonly R_SHORT_OPTIONS=",h"
readonly R_TOOL_ACTIONS="help,get-id,send-msg"
if ! parameters=$(getopt -o "$R_SHORT_OPTIONS" -l "$R_LONG_OPTIONS" -n "$0" -- "$@"); then
  exit 1
fi
eval set -- "$parameters"

while true; do
  case "$1" in
  "--app-id")
    case "$2" in
    "")
      app_id=""
      ;;
    *)
      app_id="$2"
      ;;
    esac
    shift 2
    ;;
  "--app-secret")
    case "$2" in
    "")
      app_secret=""
      ;;
    *)
      app_secret="$2"
      ;;
    esac
    shift 2
    ;;
  "--emails")
    case "$2" in
    "")
      emails=""
      ;;
    *)
      emails="$2"
      ;;
    esac
    shift 2
    ;;
  "--id-type")
    id_type="$2"
    shift 2
    ;;
  "--msg")
    msg="$2"
    shift 2
    ;;
  "--webhook")
    case "$2" in
    "")
      webhook=""
      ;;
    *)
      webhook="$2"
      ;;
    esac
    shift 2
    ;;
  "--help" | "-h")
    shift 1
    ;;
  --)
    shift
    action=$1
    echo "$R_TOOL_ACTIONS" | grep -q "$action" || error_log "Unsupported action: $action, available actions: $R_TOOL_ACTIONS"
    shift
    break
    ;;
  *)
    echo "Unknown Error: $1"
    exit 1
    ;;
  esac
done


if [ -z "$action" ]; then
  action="help"
else
  eval "action_params_check_${action//-/_}"
fi
## 脚本开始执行，执行具体的action
eval "action_${action//-/_}"


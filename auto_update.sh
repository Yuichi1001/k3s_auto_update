#!/bin/bash

# 检查是否使用 sudo 运行
if [ "$(id -u)" -ne 0 ]; then
  echo "请使用sudo运行自动更新脚本！"
  exit 1
fi

# 读取配置文件
CONFIG_FILE="auto_update.config"

if [ -f "$CONFIG_FILE" ]; then
  PROGRAM_NAME=$(grep "PROGRAM_NAME" "$CONFIG_FILE" | cut -d ' ' -f 2)
  UPDATE_URL=$(grep "UPDATE_URL" "$CONFIG_FILE" | cut -d ' ' -f 2)
  GIT_URL=$(grep "GIT_URL" "$CONFIG_FILE" | cut -d ' ' -f 2)
  TOKEN_DIR=$(grep "TOKEN_DIR" "$CONFIG_FILE" | cut -d ' ' -f 2)
  SERVER_IP=$(grep "SERVER_IP" "$CONFIG_FILE" | cut -d ' ' -f 2)
  SERVER_PORT=$(grep "SERVER_PORT" "$CONFIG_FILE" | cut -d ' ' -f 2)
  AGENT_NUM=$(grep "AGENT_NUM" "$CONFIG_FILE" | cut -d ' ' -f 2)
else
  echo "配置文件 $CONFIG_FILE 不存在。"
  exit 1
fi



# 检查配置文件中是否包含所需的配置项
if [ -z "$PROGRAM_NAME" ]; then
  echo "配置文件中没有找到 PROGRAM_NAME。"
  exit 1
fi

if [ -z "$UPDATE_URL" ]; then
  echo "配置文件中没有找到 UPDATE_URL。"
  exit 1
fi

if [ -z "$GIT_URL" ]; then
  echo "配置文件中没有找到 GIT_URL。"
  exit 1
fi

if [ -z "$TOKEN_DIR" ]; then
  echo "配置文件中没有找到 TOKEN_DIR。"
  exit 1
fi


if [ -z "$SERVER_IP" ]; then
  echo "配置文件中没有找到 SERVER_IP。"
  exit 1
fi

if [ -z "$SERVER_PORT" ]; then
  echo "配置文件中没有找到 SERVER_PORT。"
  exit 1
fi


# 定义AGENTS数组
AGENTS=()

# 遍历AGENT_NUM并获取对应的AGENT_IP
for i in $(seq 1 "$AGENT_NUM"); do
  AGENT_IP=$(grep "AGENT${i}_IP" "$CONFIG_FILE" | cut -d ':' -f 2 | tr -d ' ')
  if [ -z "$AGENT_IP" ]; then
    echo "配置文件中没有找到 AGENT${i}_IP。"
    exit 1
  fi
  AGENTS+=("$AGENT_IP")
done

# 使用 whereis 查找  PROGRAM_NAME 可执行文件的地址
PROGRAM_PATH=$(whereis "$PROGRAM_NAME" | awk '{print $2}')
# 检查是否找到  PROGRAM_NAME 可执行文件
if [ -z "$PROGRAM_PATH" ]; then
  echo "未找到  ${PROGRAM_NAME} 可执行文件。"
  exit 1
fi
PROGRAM_DIR=$(dirname "$PROGRAM_PATH")

# 获取程序版本
PROGRAM_VERSION=$($PROGRAM_DIR/"$PROGRAM_NAME" -v | grep "${PROGRAM_NAME} version" | awk '{print $3}')
echo "本地的 ${PROGRAM_NAME} 版本为 ${PROGRAM_VERSION}"

# 获取最新版本的URL并提取版本号
REDIRECT_URL=$(curl -Ls -o /dev/null -w %{url_effective} "$UPDATE_URL")
TARGET_VERSION=$(basename "$REDIRECT_URL")
echo "最新的 ${PROGRAM_NAME} 版本为 ${TARGET_VERSION}"
# 比较版本号,判断是否需要更新
if [ "$PROGRAM_VERSION" = "$TARGET_VERSION" ]; then
  echo "本地 ${PROGRAM_NAME} 已是最新版本，无须更新！"
  exit 0
else
  echo "本地 ${PROGRAM_NAME} 版本为 ${PROGRAM_VERSION} ，需要更新到版本 ${TARGET_VERSION} ，即将开始更新！"
fi


# 将 TARGET_VERSION 中的 '+' 替换为 '%2B'
TARGET_VERSION_ENCODED=$(echo "$TARGET_VERSION" | sed 's/+/%2B/g')

# 构造下载 URL
DOWNLOAD_URL="${GIT_URL}/${TARGET_VERSION_ENCODED}/${PROGRAM_NAME}"
NEW_PROGRAM_NAME="${TARGET_VERSION}_${PROGRAM_NAME}"
NEW_PROGRAM_PATH="${PROGRAM_DIR}/${NEW_PROGRAM_NAME}"
echo "下载 URL 为 ${DOWNLOAD_URL}"

# 下载最新的程序可执行文件到指定目录
wget -q --progress=bar:force:noscroll --show-progress -O "$NEW_PROGRAM_PATH" "$DOWNLOAD_URL"
echo "${TARGET_VERSION} 版本的 ${PROGRAM_NAME} 可执行文件已下载到 $PROGRAM_DIR。"


# 构造服务器进程完整名称
SERVER_NAME="${PROGRAM_NAME}-server"
# 使用 top 命令查找 PROGRAM_NAME-server 进程号。这里使用"${PROGRAM_NAME}-s"是因为top可能不会展示完整的名字，使用完整进程名字进行搜索的话可能搜索不到进程号
PROGRAM_SERVER_PID=$(top -b -n 1 | grep "${PROGRAM_NAME}-s" | awk '{print $1}')

# 检查是否找到 SERVER_NAME 进程
if [ -z "$PROGRAM_SERVER_PID" ]; then
  echo "未找到  $SERVER_NAME 进程。"
else
  # 停止 $SERVER_NAME 进程
  kill $PROGRAM_SERVER_PID
  echo "$SERVER_NAME 进程 (PID: $PROGRAM_SERVER_PID) 已停止。"
fi

#sleep 1s,防止启动新程序时端口仍旧被占用
sleep 1

# 删除  PROGRAM_NAME 可执行文件
rm -f "$PROGRAM_PATH"
echo "${PROGRAM_NAME} 可执行文件 ($PROGRAM_PATH) 已删除。"


# 将下载下来的 ${TARGET_VERSION}_$PROGRAM_NAME 重命名为 $PROGRAM_NAME
mv "$NEW_PROGRAM_PATH" "$PROGRAM_PATH"
chmod +x "$PROGRAM_PATH"
echo "${NEW_PROGRAM_NAME} 已重命名为 ${PROGRAM_NAME} 并赋予执行权限。"


echo "正在启动新版本的 ${SERVER_NAME}，启动日志输出到${PROGRAM_DIR}/${PROGRAM_NAME}.log中"

nohup $PROGRAM_DIR/$PROGRAM_NAME server > $PROGRAM_DIR/$PROGRAM_NAME.log 2>&1 &
echo "${SERVER_NAME} 更新成功！"


echo "开始更新AGENT节点！"

# 读取server节点上的node-token文件的内容
FULL_TOKEN=$(cat "$TOKEN_DIR")
# 提取需要的TOKEN值,token的示例如：K10a94918be7c61ae20ecad26d85ec2dd21b77376a4dd30ceb4d1b12f2f78e0dbef::server:32d09274ef3e6535223627fa619a5f69
#实际上只需要32d09274ef3e6535223627fa619a5f69
# 使用 ':' 分割，然后获取最后一部分，即32d09274ef3e6535223627fa619a5f69
TOKEN=$(echo "$FULL_TOKEN" | awk -F':' '{print $4}')




#按顺序更新每一个agent节点
for i in $(seq 1 "$AGENT_NUM"); do
  scp update_agent.sh root@${AGENTS[$((i-1))]}:/home/update_agent.sh
  sleep 1
  ssh root@${AGENTS[$((i-1))]} "sudo bash /home/update_agent.sh $PROGRAM_NAME $TARGET_VERSION $TOKEN $DOWNLOAD_URL $SERVER_IP $SERVER_PORT"
  echo "${AGENTS[$((i-1))]} 上的 agent 更新成功！"
done



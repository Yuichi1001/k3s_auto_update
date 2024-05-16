#!/bin/bash


PROGRAM_NAME=$1
TARGET_VERSION=$2
TOKEN=$3
DOWNLOAD_URL=$4
SERVER_IP=$5
SERVER_PORT=$6


# 使用 whereis 查找 agent节点上  PROGRAM_NAME 的可执行文件的地址
AGENT_PROGRAM_PATH=$(whereis "$PROGRAM_NAME" | awk '{print $2}')
# 检查在agent上是否找到  PROGRAM_NAME 可执行文件
if [ -z "$AGENT_PROGRAM_PATH" ]; then
  echo "未找到  ${PROGRAM_NAME} 可执行文件。"
  exit 1
fi
AGENT_PROGRAM_DIR=$(dirname "$AGENT_PROGRAM_PATH")

NEW_PROGRAM_NAME="${TARGET_VERSION}_${PROGRAM_NAME}"
AGENT_NEW_PROGRAM_PATH="${AGENT_PROGRAM_DIR}/${NEW_PROGRAM_NAME}"

# 下载最新的程序可执行文件到指定目录
wget -q --progress=bar:force:noscroll --show-progress -O "$AGENT_NEW_PROGRAM_PATH" "$DOWNLOAD_URL"
echo "${TARGET_VERSION} 版本的 ${PROGRAM_NAME} 可执行文件已下载到 $AGENT_PROGRAM_DIR。"


# 构造agent进程名称
AGENT_NAME="${PROGRAM_NAME}-agent"
# 使用 top 命令查找 PROGRAM_NAME-agent 进程号
PROGRAM_AGENT_PID=$(top -b -n 1 | grep "${PROGRAM_NAME}-a" | awk '{print $1}')

# 检查是否找到 AGENT_NAME 进程
if [ -z "$PROGRAM_AGENT_PID" ]; then
  echo "未找到  $AGENT_NAME 进程。"
else
  # 停止 $AGENT_NAME 进程
  kill $PROGRAM_AGENT_PID
  echo "$AGENT_NAME 进程 (PID: $PROGRAM_AGENT_PID) 已停止。"
fi

#sleep 1s,防止启动新程序时端口仍旧被占用
sleep 1

# 删除  PROGRAM_NAME 可执行文件
rm -f "$AGENT_PROGRAM_PATH"
echo "${PROGRAM_NAME} 可执行文件 ($AGENT_PROGRAM_PATH) 已删除。"


# 将下载下来的 ${TARGET_VERSION}_$PROGRAM_NAME 重命名为 $PROGRAM_NAME
mv "$AGENT_NEW_PROGRAM_PATH" "$AGENT_PROGRAM_PATH"
chmod +x "$AGENT_PROGRAM_PATH"
echo "${AGENT_NEW_PROGRAM_PATH} 已重命名为 ${PROGRAM_NAME} 并赋予执行权限。"


echo "正在启动新版本的 ${AGENT_NAME} ，启动日志输出到${AGENT_PROGRAM_PATH}.log中"
nohup $AGENT_PROGRAM_PATH agent -s https://$SERVER_IP:$SERVER_PORT -t $TOKEN > $AGENT_PROGRAM_PATH.log 2>&1 &

#退出ssh
exit

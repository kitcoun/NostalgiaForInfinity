#!/bin/bash    
MAIN_DATA_DIRECTORY="user_data/data"    
TIMEFRAME="5m"    
HELPER_TIME_FRAMES="1d 4h 1h 15m 1m"    
TRADING_MODE="futures"  
EXCHANGE="binance"    
URL="https://github.com/DigiTuccar/HistoricalDataForTradeBacktest.git"    
  
echo "Starting data download script..."  
echo "Configuration:"  
echo "  EXCHANGE: $EXCHANGE"  
echo "  TRADING_MODE: $TRADING_MODE"  
echo "  DATA_DIRECTORY: $MAIN_DATA_DIRECTORY"  
  
# 检查并清理现有目录(如果损坏)  
if [ -d $MAIN_DATA_DIRECTORY ]; then  
    if [ ! -d "$MAIN_DATA_DIRECTORY/.git" ]; then  
        echo "WARNING: $MAIN_DATA_DIRECTORY exists but is not a Git repository"  
        echo "Removing corrupted directory..."  
        rm -rf $MAIN_DATA_DIRECTORY  
    fi  
fi  
  
# 初始化仓库
if [ ! -d $MAIN_DATA_DIRECTORY ]; then  
    echo "Cloning repository..."  
    git clone --filter=blob:none --no-checkout --depth 1 --sparse $URL $MAIN_DATA_DIRECTORY  
      
    # 验证克隆是否成功  
    if [ ! -d "$MAIN_DATA_DIRECTORY/.git" ]; then  
        echo "ERROR: Git clone failed"  
        exit 1  
    fi  
      
    # 禁用自动 gc 以避免权限问题  
    git -C $MAIN_DATA_DIRECTORY config gc.auto 0  
      
    git -C $MAIN_DATA_DIRECTORY sparse-checkout reapply --no-cone  
fi
  
# 验证 Git 仓库  
echo "Verifying Git repository..."  
git -C $MAIN_DATA_DIRECTORY status > /dev/null 2>&1  
if [ $? -ne 0 ]; then  
    echo "ERROR: Git repository verification failed"  
    exit 1  
fi  
  
# 从配置文件提取交易对列表  
CONFIG_FILE="configs/pairlist-backtest-static-$EXCHANGE-$TRADING_MODE-usdt.json"  
echo "Reading pairs from: $CONFIG_FILE"  
  
if [ ! -f "$CONFIG_FILE" ]; then  
    echo "ERROR: Config file not found: $CONFIG_FILE"  
    exit 1  
fi  
  
jq -r .exchange.pair_whitelist[] "$CONFIG_FILE" | sed -e 's+/+_+g' -e 's+:+_+g' > ALL_PAIRS.txt  
  
PAIR_COUNT=$(wc -l < ALL_PAIRS.txt)  
echo "Found $PAIR_COUNT pairs to download"  
  
if [ "$PAIR_COUNT" -eq 0 ]; then  
    echo "ERROR: No pairs found in config file"  
    exit 1  
fi  
  
# 分批处理  
BATCH_SIZE=10    
BATCH_NUM=1  
count=0  
  
while IFS= read -r pair; do    
    echo "Processing pair: $pair (Batch $BATCH_NUM)"    
        
    # 期货市场需要 /futures 路径  
    for timeframe in $TIMEFRAME $HELPER_TIME_FRAMES; do    
        git -C $MAIN_DATA_DIRECTORY sparse-checkout add /$EXCHANGE/futures/$pair*-$timeframe*.feather  
    done    
        
    count=$((count + 1))  
    if [ $((count % BATCH_SIZE)) -eq 0 ]; then    
        echo "Checking out batch $BATCH_NUM..."    
        git -C $MAIN_DATA_DIRECTORY checkout 2>&1 | tee -a user_data/download.log    
            
        if [ $? -ne 0 ]; then    
            echo "Batch $BATCH_NUM failed, retrying..."    
            sleep 5    
            git -C $MAIN_DATA_DIRECTORY checkout 2>&1 | tee -a user_data/download.log    
        fi    
            
        echo "Batch $BATCH_NUM completed"    
        BATCH_NUM=$((BATCH_NUM + 1))    
        sleep 2  
    fi    
        
done < ALL_PAIRS.txt    
  
# 最后一批  
if [ $((count % BATCH_SIZE)) -ne 0 ]; then    
    echo "Checking out final batch..."    
    git -C $MAIN_DATA_DIRECTORY checkout 2>&1 | tee -a user_data/download.log    
fi    
  
echo "All batches completed"    
du -sh $MAIN_DATA_DIRECTORY  
  
# 验证下载的文件  
echo "Verifying downloaded files..."  
FILE_COUNT=$(find $MAIN_DATA_DIRECTORY -name "*.feather" | wc -l)  
echo "Downloaded $FILE_COUNT .feather files"
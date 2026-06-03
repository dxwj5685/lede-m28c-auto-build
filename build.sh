#!/bin/bash -x

# 检查 lede 目录是否存在
if [ ! -d "lede" ]; then
    echo "Error: 'lede' directory not found. Ensure prepare.sh ran successfully."
    exit 1
fi
cd lede || { echo "Failed to enter 'lede' directory"; exit 1; }

# 编译前磁盘空间检查
echo "=== Disk space before build ==="
df -h .
avail_kb=$(df --output=avail . | tail -1 | tr -d ' ')
if [ "$avail_kb" -lt 20000000 ]; then
    echo "WARNING: Less than 20GB free ($(( avail_kb / 1048576 ))GB), build may fail!"
fi

echo "Update feeds"
./scripts/feeds update -a || { echo "update feeds failed"; exit 1; }

echo "Install feeds"
./scripts/feeds install -a || { echo "install feeds failed"; exit 1; }

echo "Install qmodem feeds"
./scripts/feeds install -a -p qmodem || { echo "install qmodem feeds failed"; exit 1; }

# 导入配置文件并检查
if [ ! -f "../m28c.config" ]; then
    echo "Error: 'm28c.config' not found in parent directory"
    exit 1
fi
cat ../m28c.config > .config || { echo "Failed to copy m28c.config to .config"; exit 1; }

echo "Generate defconfig"
make defconfig || { echo "defconfig failed"; exit 1; }

echo "Diff between original and generated config:"
diff ../m28c.config .config || echo "Note: Config differences are normal (defconfig补充默认值)"

echo "Download dependencies (with retries)"
retry=3
while [ $retry -gt 0 ]; do
    make download -j4 && break
    retry=$((retry - 1))
    echo "Download failed, retrying... (remaining: $retry)"
    sleep 5
done
if [ $retry -eq 0 ]; then
    echo "download failed after 3 retries"
    exit 1
fi

echo "Start compiling with verbose logs (V=s, log saved to ../build.log)"
make V=s -j$(nproc) 2>&1 | tee ../build.log
ret=${PIPESTATUS[0]}

if [ $ret -ne 0 ]; then
    echo ""
    echo "========================================="
    echo "  BUILD FAILED (exit code: $ret)"
    echo "========================================="
    echo ""
    echo "=== Last 150 lines of build.log ==="
    tail -150 ../build.log
    echo ""
    echo "=== Error/Fatal lines from build.log ==="
    grep -n -i "error\|fatal\|failed\|cannot\|No such file\|undefined" ../build.log | grep -v "^[0-9]*:.*CONFIG_" | grep -v "^[0-9]*:.*#" | tail -30
    echo ""
    echo "=== Disk space after build ==="
    df -h .
    exit 1
fi

echo "Build successful!"
echo "=== Disk space after build ==="
df -h .

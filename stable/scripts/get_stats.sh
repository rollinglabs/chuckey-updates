#!/bin/bash

start_time=$(date +%s%3N)

# HOSTNAME
start_section=$(date +%s%3N)
HOST=$(hostname)

# IP ADDRESS
start_section=$(date +%s%3N)
IP=$(hostname -I | awk '{print $1}')
[ -z "$IP" ] && IP="Unavailable"

# CPU USAGE
start_section=$(date +%s%3N)
read cpu user nice system idle iowait irq softirq steal guest guest_nice < /proc/stat
prev_total=$((user + nice + system + idle + iowait + irq + softirq + steal))
prev_idle=$idle
sleep 0.1
read cpu user nice system idle iowait irq softirq steal guest guest_nice < /proc/stat
total=$((user + nice + system + idle + iowait + irq + softirq + steal))
idle=$idle

diff_total=$((total - prev_total))
diff_idle=$((idle - prev_idle))

if [ "$diff_total" -gt 0 ]; then
  CPU_USAGE=$(awk "BEGIN {printf \"%.1f%%\", 100 * ($diff_total - $diff_idle) / $diff_total}")
else
  CPU_USAGE="Unavailable"
fi

# CPU SPEED
start_section=$(date +%s%3N)
if [ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq ]; then
  CPU_SPEED=$(awk '{printf "%.0f MHz", $1/1000}' /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq)
else
  CPU_SPEED="Unavailable"
fi

# CPU LOAD (1-minute average)
start_section=$(date +%s%3N)
CPU_LOAD=$(uptime | awk -F'load average:' '{ print $2 }' | cut -d',' -f1 | xargs)
[ -z "$CPU_LOAD" ] && CPU_LOAD="Unavailable"

# CPU TEMP
start_section=$(date +%s%3N)
if [ -f /sys/class/thermal/thermal_zone0/temp ]; then
  CPU_TEMP_RAW=$(cat /sys/class/thermal/thermal_zone0/temp)
  CPU_TEMP=$(awk "BEGIN {printf \"%.1f \u00B0C\", $CPU_TEMP_RAW/1000}")
else
  CPU_TEMP="Unavailable"
fi

# MEMORY USAGE
start_section=$(date +%s%3N)
MEM_TOTAL_KB=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
MEM_AVAIL_KB=$(awk '/MemAvailable/ {print $2}' /proc/meminfo)
MEM_TOTAL=$((MEM_TOTAL_KB / 1024))" MB"
MEM_USED=$(((MEM_TOTAL_KB - MEM_AVAIL_KB) / 1024))" MB"
[ -z "$MEM_TOTAL" ] && MEM_TOTAL="Unavailable"
[ -z "$MEM_USED" ] && MEM_USED="Unavailable"

# DISK USAGE
start_section=$(date +%s%3N)
DISK_USED=$(df -h / | awk 'NR==2 {print $3}')
DISK_TOTAL=$(df -h / | awk 'NR==2 {print $2}')
[ -z "$DISK_USED" ] && DISK_USED="Unavailable"
[ -z "$DISK_TOTAL" ] && DISK_TOTAL="Unavailable"

# UPTIME
start_section=$(date +%s%3N)
if [ -f /proc/uptime ]; then
  UPTIME_SECONDS=$(awk '{print int($1)}' /proc/uptime)
  DAYS=$((UPTIME_SECONDS / 86400))
  HOURS=$(( (UPTIME_SECONDS % 86400) / 3600 ))
  MINS=$(( (UPTIME_SECONDS % 3600) / 60 ))
  UPTIME="${DAYS}d ${HOURS}h ${MINS}m"
else
  UPTIME="Unavailable"
fi

# FINAL OUTPUT
echo '{
  "hostname": "'"$HOST"'",
  "ip_address": "'"$IP"'",
  "cpu_usage": "'"$CPU_USAGE"'",
  "cpu_speed": "'"$CPU_SPEED"'",
  "cpu_load": "'"$CPU_LOAD"'",
  "cpu_temp": "'"$CPU_TEMP"'",
  "memory_used": "'"$MEM_USED"'",
  "memory_total": "'"$MEM_TOTAL"'",
  "disk_used": "'"$DISK_USED"'",
  "disk_total": "'"$DISK_TOTAL"'",
  "uptime": "'"$UPTIME"'"
}'

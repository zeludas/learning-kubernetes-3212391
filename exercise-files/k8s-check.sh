#!/usr/bin/env bash
set -euo pipefail

# --- Colors (fallback if tput unavailable) ---
if [ -t 1 ] && command -v tput >/dev/null 2>&1 && [ "$(tput colors)" -ge 8 ]; then
  RED="$(tput setaf 1)"; GREEN="$(tput setaf 2)"; YELLOW="$(tput setaf 3)"
  BLUE="$(tput setaf 4)"; MAGENTA="$(tput setaf 5)"; CYAN="$(tput setaf 6)"
  BOLD="$(tput bold)"; RESET="$(tput sgr0)"
else
  RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'
  BLUE=$'\033[34m'; MAGENTA=$'\033[35m'; CYAN=$'\033[36m'
  BOLD=$'\033[1m'; RESET=$'\033[0m'
fi

# --- Args ---
NS=""       # auto from current context by default
ALL=0
WATCH=0

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]
  -n, --namespace N   Namespace (по умолчанию: из текущего контекста, иначе 'default')
  -A, --all           Все namespace
  -w, --watch         Обновлять экран каждые 3 секунды
  -h, --help          Показать помощь
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--namespace) NS="$2"; shift 2 ;;
    -A|--all) ALL=1; shift ;;
    -w|--watch) WATCH=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) NS="$1"; shift ;;
  esac
done

# --- Resolve namespace automatically ---
if (( ALL )); then
  NS_FLAG="-A"
  NS_LABEL="all-namespaces"
else
  if [[ -z "${NS}" ]]; then
    NS="$(kubectl config view --minify --output 'jsonpath={..namespace}' || true)"
    [[ -z "${NS}" ]] && NS="default"
  fi
  NS_FLAG="-n ${NS}"
  NS_LABEL="${NS}"
fi

# --- Colorize helper ---
colorize() {
  awk -v RED="$RED" -v GREEN="$GREEN" -v YELLOW="$YELLOW" -v RESET="$RESET" '
  {
    line=$0
    # Critical / errors
    gsub(/(CrashLoopBackOff|ImagePullBackOff|ErrImagePull|CreateContainerError|OOMKilled|Evicted|NodeNotReady|Failed|BackOff|Error)/, RED"&"RESET, line)
    # Degraded / pending
    gsub(/(Pending|ContainerCreating|Init:[^ ]*|PodInitializing|Terminating|Unknown)/, YELLOW"&"RESET, line)
    # Healthy
    gsub(/(Running|Completed|Succeeded|Ready)/, GREEN"&"RESET, line)
    print line
  }'
}

# --- Header ---
header() {
  local ctx nslabel
  ctx="$(kubectl config current-context 2>/dev/null || echo "n/a")"
  nslabel="${NS_LABEL}"
  printf "%s=== K8s snapshot ===%s\n" "$BOLD" "$RESET"
  printf "%sContext:%s %s\n" "$CYAN" "$RESET" "$ctx"
  printf "%sNamespace:%s %s\n" "$CYAN" "$RESET" "$nslabel"
  printf "%sTime:%s %s\n" "$CYAN" "$RESET" "$(date '+%Y-%m-%d %H:%M:%S')"
}

# --- Sections ---
section_nodes() {
  echo
  printf "%s--- Nodes --- %s\n" "$BOLD" "$RESET"
  kubectl get nodes -o wide | colorize
}

section_pods() {
  echo
  printf "%s--- Pods (%s) --- %s\n" "$BOLD" "$NS_LABEL" "$RESET"
  kubectl get pods $NS_FLAG -o wide 2>/dev/null | colorize || echo "No pods found."
}

section_restarts() {
  echo
  printf "%s--- Top restarts (%s) --- %s\n" "$BOLD" "$NS_LABEL" "$RESET"
  # Sorted list by restart count (first container); show last 15
  if kubectl get pods $NS_FLAG --no-headers >/dev/null 2>&1; then
    kubectl get pods $NS_FLAG --sort-by='.status.containerStatuses[0].restartCount' | tail -n 15 | colorize
  else
    echo "No pods found."
  fi
}

section_events() {
  echo
  printf "%s--- Recent events (%s) --- %s\n" "$BOLD" "$NS_LABEL" "$RESET"
  # Show last 20 events
  if (( ALL )); then
    kubectl get events -A --sort-by=.lastTimestamp 2>/dev/null | tail -n 20 | colorize || echo "No events."
  else
    kubectl get events $NS_FLAG --sort-by=.lastTimestamp 2>/dev/null | tail -n 20 | colorize || echo "No events."
  fi
}

render() {
  clear
  header
  section_nodes
  section_pods
  section_restarts
  section_events
  echo
  printf "%sHints:%s problem pods: %s\n" "$MAGENTA" "$RESET" "kubectl describe pod <name> $NS_FLAG"
  printf "        logs:        %s\n" "kubectl logs <name> --tail=100 $NS_FLAG"
}

# --- Loop if watch mode ---
if (( WATCH )); then
  while true; do
    render
    sleep 3
  done
else
  render
fi

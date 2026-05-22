#!/usr/bin/env bash
# Tek tik launcher: update + server + tarayicida ac.
# Masaustu shortcut buna point eder.
#
# Akis:
#   1. flowiqa.com'dan guncelleme kontrol et
#   2. Server cevapsizsa baslat, hazir olana kadar bekle
#   3. Default tarayicida http://localhost:<port> ac

set -e
cd "$(dirname "$0")"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
say()  { echo -e "${YELLOW}>> $*${NC}"; }
ok()   { echo -e "${GREEN}   $*${NC}"; }
warn() { echo -e "${RED}   $*${NC}"; }

SERVER_PORT="${PORT:-3100}"
UPDATED=0

stop_server() {
  local pids
  pids=$(lsof -ti tcp:"$SERVER_PORT" 2>/dev/null || true)
  if [ -n "$pids" ]; then
    say "Eski server kapatiliyor (port $SERVER_PORT)..."
    echo "$pids" | xargs kill 2>/dev/null || true
    for _ in $(seq 1 10); do
      sleep 0.3
      lsof -ti tcp:"$SERVER_PORT" >/dev/null 2>&1 || { ok "Durdu"; return 0; }
    done
    # Hala canli -> SIGKILL
    pids=$(lsof -ti tcp:"$SERVER_PORT" 2>/dev/null || true)
    [ -n "$pids" ] && echo "$pids" | xargs kill -9 2>/dev/null || true
    ok "Zorla durduruldu"
  fi
}

# 1. Update check (flowiqa.com tarball)
say "Guncelleme kontrol..."
LOCAL_VERSION=$(cat data/.version 2>/dev/null || echo "")
REMOTE_VERSION=$(curl -sf --max-time 5 "https://www.flowiqa.com/api/version?app=supplier-hub" 2>/dev/null | node -e "let d=''; process.stdin.on('data', c=>d+=c); process.stdin.on('end', ()=>{ try { console.log(JSON.parse(d).version||'') } catch (e) { console.log('') } });" 2>/dev/null || echo "")

if [ -n "$REMOTE_VERSION" ] && [ "$LOCAL_VERSION" != "$REMOTE_VERSION" ]; then
  say "Yeni surum mevcut: $LOCAL_VERSION -> $REMOTE_VERSION, guncelleniyor..."
  KEY=$(node -e "try { console.log(JSON.parse(require('fs').readFileSync('data/license.json')).payload.key) } catch { console.log('') }" 2>/dev/null)
  if [ -z "$KEY" ]; then
    warn "Lisans cache yok, guncelleme atlandi (/activate'ten sonra tekrar dene)"
  else
    # Update oncesi server'i durdur (eski kod yeni dist'e takilmasin)
    stop_server
    # Re-run installer with stored key — atomik replace, .env/config korunur
    if curl -fsSL "https://www.flowiqa.com/install/supplier-hub.sh" | TARGET="$(pwd)" bash -s "$KEY" >/tmp/epc-update.log 2>&1; then
      echo "$REMOTE_VERSION" > data/.version
      ok "Guncelleme basarili: $REMOTE_VERSION"
      UPDATED=1
    else
      warn "Guncelleme basarisiz, eski surum ile devam (/tmp/epc-update.log incele)"
    fi
  fi
else
  ok "Guncel${LOCAL_VERSION:+ ($LOCAL_VERSION)}"
fi

# 2. Server
say "Server ($SERVER_PORT)..."
if [ "$UPDATED" = "1" ]; then
  # Update sonrasi force restart — yeni dist'i yukle
  stop_server
fi
if curl -sf --max-time 1 "http://localhost:$SERVER_PORT/" -o /dev/null; then
  ok "Zaten calisiyor"
else
  nohup npm start > /tmp/epc-server.log 2>&1 &
  disown 2>/dev/null || true
  for _ in $(seq 1 30); do
    sleep 0.5
    if curl -sf --max-time 1 "http://localhost:$SERVER_PORT/" -o /dev/null; then
      ok "Hazir"
      break
    fi
  done
fi

# 3. Tarayicida ac
URL="http://localhost:$SERVER_PORT"
case "$(uname)" in
  Darwin) open "$URL" ;;
  Linux) xdg-open "$URL" 2>/dev/null || true ;;
esac

echo ""
ok "Hazir: $URL"
echo "   Log: /tmp/epc-server.log"

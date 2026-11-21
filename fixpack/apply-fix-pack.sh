#!/data/data/com.termux/files/usr/bin/bash
# Применяет пакет исправлений к 3 репозиториям и пушит в main.
# Запуск (Termux или любой Linux с gh/git, авторизацией на github.com):
#   curl -sL https://raw.githubusercontent.com/palcikia-crypto/scalp-lab-termux/fixpack-other-repos/apply-fix-pack.sh | bash
set -u
BASE="https://raw.githubusercontent.com/palcikia-crypto/scalp-lab-termux/fixpack-other-repos"
WORK="${FIXPACK_WORK:-$HOME/fixpack-repos}"
mkdir -p "$WORK"

apply() {
    local repo="$1" patch="$2"
    local dir="$WORK/$repo" url="$BASE/$repo/$patch" local_patch="$WORK/$patch"
    echo "== $repo =="
    if [ -d "$dir/.git" ]; then
        git -C "$dir" fetch origin main -q || { echo "fetch failed"; return 1; }
        git -C "$dir" checkout main -q 2>/dev/null || git -C "$dir" checkout -b main origin/main -q
        git -C "$dir" reset --hard origin/main -q
    else
        git clone --quiet "https://github.com/palcikia-crypto/$repo.git" "$dir" || { echo "clone failed"; return 1; }
        git -C "$dir" checkout main -q
    fi
    curl -sL "$url" -o "$local_patch" || true
    if [ ! -s "$local_patch" ] || head -c 20 "$local_patch" | grep -q '^404'; then
        gh api -H "Accept: application/vnd.github.raw+json" \
            "repos/palcikia-crypto/scalp-lab-termux/contents/fixpack/$repo/$patch?ref=fixpack-other-repos" \
            > "$local_patch" || { echo "patch download failed (curl + gh)"; return 1; }
    fi
    [ -s "$local_patch" ] || { echo "patch empty"; return 1; }
    if git -C "$dir" am -3 "$local_patch" >/tmp/am-$repo.log 2>&1; then
        echo "patch applied"
    else
        echo "git am конфликтует (вероятно state-файлы обновились) — беру версии из патча"
        git -C "$dir" diff --name-only --diff-filter=U | while read -r f; do
            git -C "$dir" checkout --theirs -- "$f" 2>/dev/null || git -C "$dir" checkout HEAD -- "$f"
            git -C "$dir" add "$f"
        done
        git -C "$dir" -c core.editor=true am --continue >>/tmp/am-$repo.log 2>&1 || { echo "не удалось завершить git am (лог: /tmp/am-$repo.log)"; return 1; }
    fi
    python3 -m py_compile "$dir"/*.py 2>/dev/null || true
    if git -C "$dir" push origin main; then
        echo "$repo: ОТОВО, запушено в main"
    else
        echo "$repo: push не прошёл — проверь авторизацию (gh auth login) и повтори git -C $dir push origin main"
        return 1
    fi
}

apply "polymarket-lab" "0001-fix-repair-2000-char-corruption-in-14-files-settle_s.patch"
apply "scalp-lab-pro-" "0001-fix-repair-2000-char-corruption-in-6-files-pm_worker.patch"
apply "pseudo-opt-bot" "0001-risk-adaptive-drawdown-ladder-stake-x0.5-x0.25-x0.1-.patch"

if command -v gh >/dev/null 2>&1; then
    echo "— перезапускаю застрявший воркер pseudo-opt-bot"
    gh workflow run paper.yml -R palcikia-crypto/pseudo-opt-bot 2>/dev/null && echo "paper.yml запущен" || echo "не удалось запустить через gh (не критично — запустится по расписанию)"
fi

echo
echo "Готово. Воркеры подхватят изменения в ближайший запуск по расписанию."

===============[ this is a help package that fix some packages-root-derectory-system ] ===================





===============[ Commands ] ===================
✅ dpkg Repair (recommended)
sudo tools/dpkg-emergency-repair.sh



✅ 1) Full Automatic Repair (recommended)

Repairs everything: dpkg, apt, python, venv, systemd, services, fallback, self-heal.

sudo tools/emergency-total-repair.sh --full-auto --self-heal --repair-systemd --wget-fallback --restart-agent --non-interactive

✅ 2) Standard One-Shot Emergency Repair

Runs 1 cycle, no loop.

sudo tools/emergency-total-repair.sh --full-auto --repair-systemd --wget-fallback --restart-agent

✅ 3) Minimal dpkg/apt repair only
sudo tools/emergency-total-repair.sh --full-auto

✅ 4) Repair python core + recreate venv
sudo tools/emergency-total-repair.sh --full-auto --venv-path /opt/ai-agent/venv --target /opt/ai-agent

✅ 5) Systemd repair only (no venv/python)
sudo tools/emergency-total-repair.sh --repair-systemd

✅ 6) Self-heal loop (up to 10 cycles)
sudo tools/emergency-total-repair.sh --self-heal --full-auto --non-interactive

✅ 7) Restart services only
sudo tools/emergency-total-repair.sh --restart-agent

✅ 8) Enable wget fallback only
sudo tools/emergency-total-repair.sh --wget-fallback

✅ 9) Check + repair with custom venv location
sudo tools/emergency-total-repair.sh --venv-path /custom/venv --target /custom/project

❗ Useful Quick Aliases
Repair & restart (safe default):
sudo tools/emergency-total-repair.sh --full-auto --restart-agent

Maximum damage-control mode:
sudo tools/emergency-total-repair.sh --full-auto --self-heal --wget-fallback --repair-systemd --restart-agent --non-interactive



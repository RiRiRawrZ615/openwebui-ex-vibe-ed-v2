Name:           openwebvibes-v2
Version:        1.2.0
Release:        1.rc1
Summary:        Open Web Vibes v2: the visual layer on clean Open WebUI, with optional billion-context
License:        MIT
Source0:        openwebvibes-v2.tar.gz
BuildArch:      noarch

Requires:       bash
Requires:       python3
Requires:       tmux
Requires:       curl

# Deliberately NOT conflicting with openwebvibes. The two packages are meant to be installed
# side by side on one machine: v1 keeps the context gate, v2 is the visual layer. Everything
# this package touches is under a v2 name-space (install root, /etc, profile.d, s6, systemd,
# /usr/bin/owv-v2, and the runtime/data/state dirs the launcher derives), so no file here can
# overwrite a file owned by the v1 package. Ports differ too, so both can run at once.
Provides:       openwebvibes(v2)

%description
Open Web Vibes v2. Frontend/visual layer only, on clean upstream Open WebUI: theming, the stats
row, tool-call rendering, the settings UI. No context gate, no journal, no reconstruction, no
compaction, no prompt rewriting. The backend kept is just the slim settings/theme/stats router.

Context management is optional and lives in front of the engine, not inside the app: an
OpenAI-compatible proxy (billion-context) can sit between Open WebUI and the engine without
touching the backend. It is off by default so plain runs are untouched. Enable with
OWV_CONTEXT_PROXY=1.

Co-installable with openwebvibes (v1). v2 runs on its own ports (webui 8085, api 8005, terminal
8006, vision 8007) and its own data/runtime/state dirs, so v1 on 8080 and v2 on 8085 can both
serve at the same time. Entry point is owv-v2.

%prep
%setup -q -n openwebvibes-v2

%install
rm -rf "%{buildroot}"
install -d -m 755 "%{buildroot}/usr/lib/openwebvibes-v2"
install -d -m 755 "%{buildroot}/usr/lib/openwebvibes-v2/launcher"
install -d -m 755 "%{buildroot}/usr/bin"
install -d -m 755 "%{buildroot}/etc/openwebvibes-v2"
install -d -m 755 "%{buildroot}/etc/s6-overlay/s6-rc.d/openwebvibes-v2"
install -d -m 755 "%{buildroot}/etc/profile.d"
install -d -m 755 "%{buildroot}/usr/lib/systemd/system"

cp -a backend "%{buildroot}/usr/lib/openwebvibes-v2/"
cp -a build "%{buildroot}/usr/lib/openwebvibes-v2/"

# The engine wrapper is the v2-specific piece: BACKEND=llama|strata|auto, optional proxy route,
# nothing hardcoded to a machine. It ships because it is the thing that makes a packaged v2
# install actually runnable.
install -d -m 755 "%{buildroot}/usr/lib/openwebvibes-v2/engine"
cp -a engine/. "%{buildroot}/usr/lib/openwebvibes-v2/engine/"

# env.py reads CHANGELOG.md at import time, so the packaged tree needs it.
if [ -f CHANGELOG.md ]; then
    install -m 644 CHANGELOG.md "%{buildroot}/usr/lib/openwebvibes-v2/CHANGELOG.md"
fi

install -m 755 packaging/launcher/owv.sh "%{buildroot}/usr/lib/openwebvibes-v2/launcher/owv.sh"
install -m 755 packaging/launcher/owv-packaged.sh "%{buildroot}/usr/lib/openwebvibes-v2/launcher/owv-packaged.sh"
install -m 755 packaging/launcher/owv-kill.sh "%{buildroot}/usr/lib/openwebvibes-v2/launcher/owv-kill.sh"
install -m 755 packaging/launcher/owv-aliases.sh "%{buildroot}/usr/lib/openwebvibes-v2/launcher/owv-aliases.sh"
install -m 755 packaging/launcher/owv-status.sh "%{buildroot}/usr/lib/openwebvibes-v2/launcher/owv-status.sh"
install -m 755 packaging/install-detect.sh "%{buildroot}/usr/lib/openwebvibes-v2/install-detect.sh"
install -m 755 packaging/ensure-open-terminal.sh "%{buildroot}/usr/lib/openwebvibes-v2/ensure-open-terminal.sh"
install -m 755 packaging/ensure-venv.sh "%{buildroot}/usr/lib/openwebvibes-v2/ensure-venv.sh"
ln -s ../lib/openwebvibes-v2/launcher/owv-packaged.sh "%{buildroot}/usr/bin/owv-v2"

install -m 644 packaging/etc/openwebvibes-v2/owv.conf "%{buildroot}/etc/openwebvibes-v2/owv.conf"
install -m 644 packaging/profile.d/openwebvibes-v2.sh "%{buildroot}/etc/profile.d/openwebvibes-v2.sh"
install -m 644 packaging/s6/openwebvibes-v2/type "%{buildroot}/etc/s6-overlay/s6-rc.d/openwebvibes-v2/type"
install -m 755 packaging/s6/openwebvibes-v2/run "%{buildroot}/etc/s6-overlay/s6-rc.d/openwebvibes-v2/run"
install -m 644 packaging/systemd/openwebvibes-v2.service "%{buildroot}/usr/lib/systemd/system/openwebvibes-v2.service"

%post
install -d -m 755 /var/lib/openwebvibes-v2 2>/dev/null || true

/usr/lib/openwebvibes-v2/install-detect.sh > /var/lib/openwebvibes-v2/install-report.json 2>/dev/null || true

# A noarch package never builds an environment, so a fresh machine gets the fork code with nothing
# to start: no venv, no importable module, and the launcher refuses later with a missing-module
# message. That is the gap a release has to close for someone who is not already running this
# stack. Ensure the venv once, bounded, and non-fatal, so an offline install still completes.
# Skip entirely with OWV_RPM_BOOTSTRAP_VENV=0.
if [ "${OWV_RPM_BOOTSTRAP_VENV:-1}" = "1" ]; then
    /usr/lib/openwebvibes-v2/ensure-venv.sh > /var/lib/openwebvibes-v2/venv-report.json 2>/dev/null || true
fi

/usr/lib/openwebvibes-v2/ensure-open-terminal.sh > /var/lib/openwebvibes-v2/open-terminal-report.json 2>/dev/null || true

%files
/usr/lib/openwebvibes-v2
/usr/bin/owv-v2
/etc/openwebvibes-v2/owv.conf
/etc/profile.d/openwebvibes-v2.sh
/etc/s6-overlay/s6-rc.d/openwebvibes-v2
/usr/lib/systemd/system/openwebvibes-v2.service

%changelog
* Tue Nov 10 2026 Qwen 3.8 <qwen@localhost> - 1.2.0-1.rc1
- First v2 release. Package renamed openwebvibes-v2 so it is co-installable with v1: separate
  install root, /etc, profile.d, s6 service, systemd unit, /usr/bin/owv-v2, runtime/data/state dirs.
- Ports separated from v1 and from the stock instance: webui 8085, api 8005, terminal 8006,
  vision 8007. v1 on 8080 and v2 on 8085 can serve at the same time.
- Launcher: the two remaining calls into the dropped gate modules (backend decision, handshake)
  replaced. v2 has no ex_backend/ex_handshake, so the decision is env-driven and the handshake
  record is written directly in the same shape the settings tab reads. Previously a packaged v2
  boot died at the backend decision.
- Aliases namespaced per version: owv-v2, kill-owv-v2, owv-v2-status.
- Added packaging/ensure-venv.sh: creates the fork venv and installs requirements once at install
  time when absent, bounded and non-fatal, so a fresh machine can actually run the package.
- Frontend build verified (265 MB bundle, pyodide included); isolated boot verified answering
  health 200 and the frontend 200 against the engine.

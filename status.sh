#!/usr/bin/env python3
import json
import os
import subprocess
import sys
import urllib.request
import urllib.error

# Re-exec under local .venv if available
script_dir = os.path.dirname(os.path.realpath(__file__))
venv_python = os.path.join(script_dir, ".venv", "bin", "python3")
if os.path.exists(venv_python) and sys.executable != venv_python:
    os.execv(venv_python, [venv_python] + sys.argv)

import yaml

# Determine Podman wrapper command
podman_bin = "podman"
if os.path.exists("/run/.containerenv"):
    if subprocess.run("command -v distrobox-host-exec >/dev/null 2>&1", shell=True).returncode == 0:
        podman_bin = "distrobox-host-exec podman"
    elif subprocess.run("command -v flatpak-spawn >/dev/null 2>&1", shell=True).returncode == 0:
        podman_bin = "flatpak-spawn --host podman"

print("======================================================================")
print("                     ACTIVE VMS & GITHUB RUNNERS                      ")
print("======================================================================")

print("LIMA VIRTUAL MACHINE METADATA:")

# Query limactl JSON output for detailed VM specifications
vm_cmd = f"{podman_bin} exec -u lima lima-vm-container limactl list --json github-runner"
res = subprocess.run(vm_cmd, shell=True, capture_output=True, text=True)

vm_info = {}
if res.returncode == 0 and res.stdout.strip():
    try:
        vm_info = json.loads(res.stdout.strip().split("\n")[0])
    except Exception:
        pass

if vm_info:
    name = vm_info.get("name", "github-runner")
    status = vm_info.get("status", "Unknown")
    arch = vm_info.get("arch", "Unknown")
    cpus = vm_info.get("cpus", "N/A")
    memory = vm_info.get("memory", "N/A")
    disk = vm_info.get("disk", "N/A")
    ssh_addr = vm_info.get("sshAddress", "N/A")
    ssh_port = vm_info.get("sshLocalPort", "N/A")
    vm_dir = vm_info.get("dir", "N/A")
    vm_type = vm_info.get("vmType", "qemu")

    if isinstance(memory, (int, float)):
        memory = f"{round(memory / (1024**3), 2)} GB"
    if isinstance(disk, (int, float)):
        disk = f"{round(disk / (1024**3), 2)} GB"

    print(f"  - VM Name:      {name}")
    print(f"    Status:       {status}")
    print(f"    Architecture: {arch}")
    print(f"    VM Type:      {vm_type}")
    print(f"    CPUs / RAM:   {cpus} vCPUs / {memory}")
    print(f"    Disk Size:    {disk}")
    print(f"    SSH Endpoint: {ssh_addr}:{ssh_port}")
    print(f"    VM Directory: {vm_dir}")

    if str(status).lower() == "running":
        guest_cmd = f"{podman_bin} exec -u lima lima-vm-container limactl shell github-runner -- bash -c 'source /etc/os-release 2>/dev/null && echo \"$PRETTY_NAME|$(uname -r)|$(uptime -p 2>/dev/null || uptime)|$(hostname -I 2>/dev/null | awk \"{{print $1}}\")\"'"
        guest_res = subprocess.run(guest_cmd, shell=True, capture_output=True, text=True)
        if guest_res.returncode == 0 and guest_res.stdout.strip():
            g_parts = guest_res.stdout.strip().split("|")
            if len(g_parts) >= 4:
                print(f"    Guest OS:     {g_parts[0]}")
                print(f"    Kernel:       {g_parts[1]}")
                print(f"    Uptime:       {g_parts[2]}")
                print(f"    Guest IP:     {g_parts[3]}")
else:
    print("  No active Lima VM found or unable to query metadata.")

# Load GitHub PAT from Ansible Vault or environment
github_pat = os.environ.get("GITHUB_PAT")
vault_file = os.path.join(script_dir, "vars", "vault.yml")
vault_pass_file = os.path.join(script_dir, ".secrets", "ansible_vault_pass")

if not github_pat and os.path.exists(vault_file) and os.path.exists(vault_pass_file):
    try:
        v_cmd = f"ansible-vault view --vault-password-file {vault_pass_file} {vault_file}"
        v_res = subprocess.run(v_cmd, shell=True, capture_output=True, text=True)
        if v_res.returncode == 0:
            v_data = yaml.safe_load(v_res.stdout) or {}
            github_pat = v_data.get("github_pat") or v_data.get("vault_github_pat")
    except Exception:
        pass

def get_github_runner_status(owner, repo, runner_name, pat):
    if not pat:
        return "N/A (Vault/PAT unavailable)"
    url = f"https://api.github.com/repos/{owner}/{repo}/actions/runners"
    req = urllib.request.Request(url)
    req.add_header("Authorization", f"Bearer {pat}")
    req.add_header("Accept", "application/vnd.github+json")
    req.add_header("X-GitHub-Api-Version", "2022-11-28")
    req.add_header("User-Agent", "Ansible-Runner-Status-Script")

    try:
        with urllib.request.urlopen(req, timeout=5) as resp:
            if resp.status == 200:
                data = json.loads(resp.read().decode())
                for r in data.get("runners", []):
                    if r.get("name") == runner_name:
                        st = r.get("status", "unknown")
                        busy = r.get("busy", False)
                        state_str = "Busy / Running Job" if busy else "Idle"
                        return f"{st.capitalize()} ({state_str})"
                return "Not Registered"
    except urllib.error.HTTPError as e:
        return f"API Error ({e.code})"
    except Exception as e:
        return f"Connection Failed ({type(e).__name__})"
    return "Unknown"

print("\nACTIVE RUNNERS & METADATA:")
runner_meta = {}
runners_file = os.path.join(script_dir, "vars", "runners.yml")

if os.path.exists(runners_file):
    try:
        with open(runners_file, "r") as f:
            data = yaml.safe_load(f) or {}
            for r in data.get("github_runners", []):
                runner_meta[r.get("name")] = {
                    "owner": r.get("owner"),
                    "repo_name": r.get("repo"),
                    "repo": f"{r.get('owner')}/{r.get('repo')}",
                    "labels": r.get("labels", "None"),
                    "devices": ", ".join(r.get("devices", [])) if isinstance(r.get("devices"), list) else str(r.get("devices", "None"))
                }
    except Exception:
        pass

ps_cmd = f"{podman_bin} exec -u lima lima-vm-container limactl shell github-runner sudo podman ps --format '{{{{.Names}}}}|{{{{.ID}}}}|{{{{.Image}}}}|{{{{.Status}}}}'"
res = subprocess.run(ps_cmd, shell=True, capture_output=True, text=True)

lines = [l.strip() for l in res.stdout.strip().split("\n") if l.strip()]
if not lines or res.returncode != 0:
    print("  No active runner containers found.")
else:
    for line in lines:
        parts = line.split("|")
        c_name = parts[0]
        c_id = parts[1][:12] if len(parts) > 1 else "Unknown"
        c_image = parts[2] if len(parts) > 2 else "Unknown"
        c_status = parts[3] if len(parts) > 3 else "Unknown"
        
        meta = runner_meta.get(c_name, {})
        owner = meta.get("owner")
        repo_name = meta.get("repo_name")
        repo = meta.get("repo", "Unmapped Repo")
        labels = meta.get("labels", "N/A")
        devices = meta.get("devices", "N/A")

        gh_status = "N/A"
        if owner and repo_name:
            gh_status = get_github_runner_status(owner, repo_name, c_name, github_pat)

        print(f"  - Runner Name:    {c_name}")
        print(f"    Repository:     {repo}")
        print(f"    GitHub Status:  {gh_status}")
        print(f"    Local Status:   {c_status}")
        print(f"    Container ID:   {c_id}")
        print(f"    Image:          {c_image}")
        print(f"    Labels:         {labels}")
        print(f"    Devices:        {devices}\n")

print("======================================================================")


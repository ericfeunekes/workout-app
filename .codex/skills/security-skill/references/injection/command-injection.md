# Command Injection Prevention

Command injection occurs when user input is passed to shell commands, allowing attackers to execute arbitrary system commands.

## The Problem

```python
import os
import subprocess

# VULNERABLE - os.system with user input
os.system(f"grep -r {search_term} /var/log")

# VULNERABLE - subprocess with shell=True
subprocess.run(f"ls -la {directory}", shell=True)

# VULNERABLE - string concatenation
subprocess.call("echo " + user_input, shell=True)

# VULNERABLE - bash -c with user input
subprocess.run(["bash", "-c", user_command])
```

## Primary Defense: Avoid shell=True + Use Arrays

```python
# SAFE - array arguments, no shell interpretation
subprocess.run(["grep", "-r", search_term, "/var/log"])

# SAFE - Popen with array
process = subprocess.Popen(
    ["ls", "-la", directory],
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE
)

# SAFE - check_output with array
output = subprocess.check_output(["cat", file_path])
```

## Why shell=True is Dangerous

With `shell=True`, the command is passed through `/bin/sh -c`, enabling:
- Command chaining: `; rm -rf /`
- Command substitution: `$(whoami)`
- Piping: `| cat /etc/passwd`
- Redirects: `> /tmp/pwned`
- Environment variable expansion: `$HOME`

```python
# With shell=True, this input:
user_input = "file.txt; rm -rf /"

# Becomes this command:
subprocess.run(f"cat {user_input}", shell=True)
# Executes: sh -c "cat file.txt; rm -rf /"
```

## Safe Patterns by Use Case

### Running External Commands

```python
import subprocess
import shlex

# SAFE - array form, no shell
def list_directory(path: str) -> str:
    result = subprocess.run(
        ["ls", "-la", path],
        capture_output=True,
        text=True,
        check=True  # Raise on non-zero exit
    )
    return result.stdout

# SAFE - with timeout and error handling
def run_command(args: list[str], timeout: int = 30) -> str:
    try:
        result = subprocess.run(
            args,
            capture_output=True,
            text=True,
            timeout=timeout,
            check=True
        )
        return result.stdout
    except subprocess.TimeoutExpired:
        raise RuntimeError("Command timed out")
    except subprocess.CalledProcessError as e:
        raise RuntimeError(f"Command failed: {e.stderr}")
```

### When You Need Shell Features

If you genuinely need shell features (pipes, redirects), don't use user input:

```python
# SAFE - hardcoded shell command, no user input
subprocess.run("ls -la | grep .py", shell=True)

# SAFE - parameterize after the shell part
# Use shlex.quote for any user-provided values
import shlex

def search_logs(pattern: str) -> str:
    # Quote the pattern to prevent injection
    safe_pattern = shlex.quote(pattern)
    # Still risky - prefer array form if possible
    result = subprocess.run(
        f"grep {safe_pattern} /var/log/app.log",
        shell=True,
        capture_output=True,
        text=True
    )
    return result.stdout
```

### Parsing Command Strings

If you receive a command string and need to split it safely:

```python
import shlex

# SAFE - shlex.split handles quoting correctly
command_string = "ls -la '/path/with spaces/file.txt'"
args = shlex.split(command_string)
# args = ['ls', '-la', '/path/with spaces/file.txt']

subprocess.run(args)  # No shell=True needed
```

### Input Validation

When you must accept some user input:

```python
import re
from pathlib import Path

ALLOWED_COMMANDS = {"ls", "cat", "head", "tail", "grep"}

def run_safe_command(command: str, target: str) -> str:
    # Allowlist the command
    if command not in ALLOWED_COMMANDS:
        raise ValueError(f"Command not allowed: {command}")

    # Validate target is a safe path
    target_path = Path(target).resolve()
    if not target_path.is_relative_to(Path("/var/log")):
        raise ValueError("Target must be in /var/log")

    # Use array form
    return subprocess.run(
        [command, str(target_path)],
        capture_output=True,
        text=True,
        check=True
    ).stdout
```

## Dangerous Functions to Audit

| Function | Risk | Notes |
|----------|------|-------|
| `os.system()` | Critical | Always uses shell |
| `os.popen()` | Critical | Always uses shell |
| `subprocess.*(..., shell=True)` | Critical | Shell interpretation enabled |
| `subprocess.run(["bash", "-c", ...])` | Critical | Explicit shell invocation |
| `os.spawn*()` | High | Can invoke shell |
| `os.exec*()` | High | Can invoke shell |
| `asyncio.create_subprocess_shell()` | Critical | Async shell execution |
| `Popen(..., shell=True)` | Critical | Shell interpretation |

## Async Command Execution

```python
import asyncio

# VULNERABLE
await asyncio.create_subprocess_shell(f"ls {user_input}")

# SAFE - use create_subprocess_exec with array
process = await asyncio.create_subprocess_exec(
    "ls", "-la", directory,
    stdout=asyncio.subprocess.PIPE,
    stderr=asyncio.subprocess.PIPE
)
stdout, stderr = await process.communicate()
```

## Wildcard Poisoning

Wildcards can be exploited via specially-named files:

```bash
# If a file named "-rf" exists:
$ ls
-rf  important_data/

# This becomes dangerous:
$ rm *
# Expands to: rm -rf important_data/
```

```python
# AVOID wildcards in subprocess calls
# Instead, use Python's glob
from pathlib import Path

files = list(Path("/var/log").glob("*.log"))
for f in files:
    subprocess.run(["cat", str(f)])
```

## Prefer Python APIs

| Instead of | Use |
|------------|-----|
| `os.system("mkdir dir")` | `os.makedirs("dir")` |
| `os.system("rm file")` | `os.remove("file")` |
| `os.system("cp a b")` | `shutil.copy("a", "b")` |
| `os.system("mv a b")` | `shutil.move("a", "b")` |
| `os.system("ls dir")` | `os.listdir("dir")` |
| `os.system("cat file")` | `Path("file").read_text()` |
| `os.system("chmod 755 f")` | `os.chmod("f", 0o755)` |

## Semgrep Rules

```bash
semgrep --config r/python.lang.security.audit.dangerous-subprocess-use
semgrep --config r/python.lang.security.audit.subprocess-shell-true
semgrep --config r/python.lang.security.audit.dangerous-system-call
semgrep --config r/python.lang.security.audit.dangerous-spawn-process
```

## Testing

```python
def test_command_injection_blocked():
    malicious = "; rm -rf /"

    # This should NOT execute rm
    with pytest.raises(ValueError):
        run_safe_command("ls", malicious)

    # Or if it runs, it should treat the whole string as a filename
    result = list_directory(malicious)
    assert "rm" not in result  # Didn't execute
```

## References

- Semgrep Python Command Injection Cheat Sheet
- OWASP OS Command Injection Defense Cheat Sheet
- Python subprocess documentation

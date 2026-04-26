# Deserialization Safety

Deserializing untrusted data can lead to arbitrary code execution. Attackers craft payloads that execute code during the deserialization process.

## The Problem

```python
import pickle
import yaml

# VULNERABLE - pickle with untrusted data
data = pickle.loads(untrusted_bytes)  # Arbitrary code execution

# VULNERABLE - yaml.load without safe loader
config = yaml.load(untrusted_yaml)  # Arbitrary code execution

# VULNERABLE - pickle from file
with open(user_provided_path, "rb") as f:
    data = pickle.load(f)
```

## Why Pickle is Dangerous

Pickle can execute arbitrary Python code during deserialization:

```python
# Attacker payload that executes commands
import pickle
import os

class Exploit:
    def __reduce__(self):
        return (os.system, ("whoami",))

# This creates a pickle that runs "whoami" when loaded
payload = pickle.dumps(Exploit())

# When victim loads this:
pickle.loads(payload)  # Executes: os.system("whoami")
```

Real payloads can:
- Execute shell commands
- Download and run malware
- Exfiltrate data
- Establish reverse shells

## Safe Alternatives

### Use JSON (Preferred)

```python
import json
from dataclasses import dataclass, asdict
from typing import Any

@dataclass
class User:
    id: int
    name: str
    email: str

# Serialize
def to_json(user: User) -> str:
    return json.dumps(asdict(user))

# Deserialize with type enforcement
def from_json(data: str) -> User:
    parsed = json.loads(data)
    return User(
        id=int(parsed["id"]),
        name=str(parsed["name"]),
        email=str(parsed["email"])
    )
```

### Use Pydantic for Validation

```python
from pydantic import BaseModel, EmailStr

class UserModel(BaseModel):
    id: int
    name: str
    email: EmailStr

# Safe deserialization with validation
def parse_user(data: str) -> UserModel:
    return UserModel.model_validate_json(data)

# Rejects invalid data
parse_user('{"id": "not_an_int", "name": "test", "email": "bad"}')
# Raises ValidationError
```

### YAML with Safe Loader

```python
import yaml

# SAFE - yaml.safe_load only allows basic types
config = yaml.safe_load(yaml_string)

# SAFE - explicit SafeLoader
config = yaml.load(yaml_string, Loader=yaml.SafeLoader)

# For full YAML features without code execution:
# yaml.FullLoader is safer than yaml.Loader but still has risks
# Prefer safe_load when possible
```

### MessagePack (Binary, No Code Execution)

```python
import msgpack

# Serialize
data = msgpack.packb({"key": "value", "number": 42})

# Deserialize - safe, no code execution
result = msgpack.unpackb(data)
```

## When You Must Use Pickle

If pickle is unavoidable (legacy systems, ML models), add integrity protection:

### HMAC Signing

```python
import hashlib
import hmac
import pickle
import secrets

class SecurePickle:
    def __init__(self, key: bytes):
        self._key = key

    def dumps(self, obj) -> tuple[bytes, str]:
        """Serialize with HMAC signature."""
        data = pickle.dumps(obj)
        signature = hmac.new(
            self._key, data, hashlib.sha256
        ).hexdigest()
        return data, signature

    def loads(self, data: bytes, signature: str):
        """Verify signature before deserializing."""
        expected = hmac.new(
            self._key, data, hashlib.sha256
        ).hexdigest()

        if not hmac.compare_digest(signature, expected):
            raise ValueError("Invalid signature - data may be tampered")

        return pickle.loads(data)

# Usage
key = secrets.token_bytes(32)  # Store securely!
sp = SecurePickle(key)

# Serialize
data, sig = sp.dumps({"user": "alice"})

# Deserialize - verifies integrity first
result = sp.loads(data, sig)
```

### Restrict Unpickler Classes

```python
import pickle
import io

ALLOWED_CLASSES = {
    ("builtins", "dict"),
    ("builtins", "list"),
    ("builtins", "str"),
    ("builtins", "int"),
    ("myapp.models", "User"),
}

class RestrictedUnpickler(pickle.Unpickler):
    def find_class(self, module, name):
        if (module, name) not in ALLOWED_CLASSES:
            raise pickle.UnpicklingError(
                f"Class {module}.{name} not allowed"
            )
        return super().find_class(module, name)

def safe_loads(data: bytes):
    return RestrictedUnpickler(io.BytesIO(data)).load()
```

## ML Model Files

ML model files (`.pkl`, `.joblib`, `.pt`) often use pickle internally:

```python
# VULNERABLE - loading untrusted model
import joblib
model = joblib.load("untrusted_model.pkl")

# SAFER - use safetensors for PyTorch
from safetensors.torch import load_file
weights = load_file("model.safetensors")

# SAFER - verify model source
import hashlib
def load_verified_model(path: str, expected_hash: str):
    with open(path, "rb") as f:
        data = f.read()

    actual_hash = hashlib.sha256(data).hexdigest()
    if actual_hash != expected_hash:
        raise ValueError("Model file hash mismatch")

    return joblib.load(path)
```

## Other Dangerous Deserializers

| Format | Dangerous Function | Safe Alternative |
|--------|-------------------|------------------|
| Pickle | `pickle.loads()` | JSON, msgpack, protobuf |
| YAML | `yaml.load()` | `yaml.safe_load()` |
| XML | `xml.etree` with entities | `defusedxml` |
| Marshal | `marshal.loads()` | Don't use for untrusted data |
| Shelve | `shelve.open()` | Uses pickle internally |

### XML External Entity (XXE)

```python
# VULNERABLE - allows external entities
import xml.etree.ElementTree as ET
tree = ET.parse(untrusted_xml)

# SAFE - use defusedxml
import defusedxml.ElementTree as ET
tree = ET.parse(untrusted_xml)  # Blocks XXE attacks
```

## Semgrep Rules

```bash
semgrep --config r/python.lang.security.deserialization.avoid-pickle
semgrep --config r/python.lang.security.deserialization.avoid-pyyaml-load
semgrep --config r/python.lang.security.audit.marshal-usage
```

## CVE Examples

| Product | CVE | Description | CVSS |
|---------|-----|-------------|------|
| TensorFlow | CVE-2021-37678 | RCE via YAML model deserialization | 8.8 |
| NVFLARE | CVE-2022-34668 | RCE via pickle | 9.8 |
| Superset | CVE-2018-8021 | RCE via pickle | 9.8 |
| rpc.py | CVE-2022-35411 | RCE via HTTP header pickle | 9.8 |

## Detection Patterns

```python
# Patterns to flag during code review:

# Direct pickle usage with external input
pickle.loads(request.body)
pickle.load(open(user_path, "rb"))

# YAML without safe loader
yaml.load(config_string)
yaml.load(file, Loader=yaml.Loader)
yaml.load(file, Loader=yaml.FullLoader)  # Still risky

# Joblib/sklearn with untrusted files
joblib.load(uploaded_file)
torch.load(model_path)  # Uses pickle
```

## Testing

```python
def test_rejects_pickle_payload():
    """Ensure pickle payloads are rejected."""
    import pickle
    import os

    class Exploit:
        def __reduce__(self):
            return (os.system, ("echo pwned",))

    payload = pickle.dumps(Exploit())

    # Should reject or raise
    with pytest.raises(ValueError):
        process_data(payload)

def test_yaml_safe_load():
    """Ensure YAML uses safe loader."""
    malicious_yaml = "!!python/object/apply:os.system ['echo pwned']"

    # Should raise, not execute
    with pytest.raises(yaml.YAMLError):
        yaml.safe_load(malicious_yaml)
```

## References

- OpenSSF Secure Coding Guide for Python (CWE-502)
- OWASP Deserialization Cheat Sheet
- Bandit B301 (pickle usage)

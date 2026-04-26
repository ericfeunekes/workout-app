# File Upload Security

File uploads are a common attack vector. Malicious files can execute code, overwrite system files, or exploit processing vulnerabilities.

## Threats

| Threat | Description | Example |
|--------|-------------|---------|
| **Code Execution** | Uploaded file executed on server | `.php`, `.jsp`, `.py` in webroot |
| **Path Traversal** | Filename escapes upload directory | `../../../etc/cron.d/backdoor` |
| **Content Spoofing** | File type doesn't match extension | `.jpg` containing PHP code |
| **DoS** | Large files or zip bombs | 42.zip (4.5 PB decompressed) |
| **Malware** | Infected files served to users | Macro-enabled Office docs |
| **XSS** | HTML/SVG uploaded and served | `image.svg` with `<script>` |

## Defense in Depth

Apply multiple layers - no single check is sufficient.

### 1. Extension Allowlist

```python
from pathlib import Path

ALLOWED_EXTENSIONS = {".pdf", ".docx", ".xlsx", ".png", ".jpg", ".jpeg"}

def validate_extension(filename: str) -> str:
    """Validate file extension against allowlist."""
    ext = Path(filename).suffix.lower()

    # Handle double extensions
    if filename.lower().endswith(('.php', '.jsp', '.exe', '.sh', '.py')):
        raise ValueError("Executable extension not allowed")

    if ext not in ALLOWED_EXTENSIONS:
        raise ValueError(f"Extension {ext} not allowed")

    return ext
```

### 2. Content-Type Validation (Weak)

Content-Type is user-controlled - use only as quick filter, not security:

```python
ALLOWED_CONTENT_TYPES = {
    "application/pdf",
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    "image/png",
    "image/jpeg",
}

def validate_content_type(content_type: str):
    """Quick filter - NOT a security control."""
    if content_type not in ALLOWED_CONTENT_TYPES:
        raise ValueError(f"Content type {content_type} not allowed")
```

### 3. Magic Bytes Validation

Check actual file content, not just headers:

```python
import magic  # python-magic library

MAGIC_TYPE_MAP = {
    ".pdf": "application/pdf",
    ".png": "image/png",
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    ".xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
}

def validate_magic_bytes(file_bytes: bytes, expected_ext: str):
    """Validate file content matches expected type."""
    detected = magic.from_buffer(file_bytes, mime=True)
    expected = MAGIC_TYPE_MAP.get(expected_ext)

    if detected != expected:
        raise ValueError(
            f"File content ({detected}) doesn't match extension ({expected_ext})"
        )
```

### 4. Filename Sanitization

```python
import re
import uuid
from pathlib import Path

def sanitize_filename(filename: str) -> str:
    """Generate safe filename, preserving extension."""
    ext = Path(filename).suffix.lower()

    # Validate extension first
    if ext not in ALLOWED_EXTENSIONS:
        raise ValueError(f"Extension not allowed: {ext}")

    # Generate random filename
    return f"{uuid.uuid4()}{ext}"

def sanitize_user_filename(filename: str) -> str:
    """If original filename must be preserved."""
    # Remove path components
    filename = Path(filename).name

    # Remove null bytes
    filename = filename.replace('\x00', '')

    # Allow only safe characters
    filename = re.sub(r'[^a-zA-Z0-9._-]', '_', filename)

    # Prevent hidden files
    filename = filename.lstrip('.')

    # Limit length
    name, ext = filename.rsplit('.', 1) if '.' in filename else (filename, '')
    if ext:
        return f"{name[:200]}.{ext[:10]}"
    return name[:200]
```

### 5. Size Limits

```python
MAX_FILE_SIZE = 10 * 1024 * 1024  # 10 MB
MAX_REQUEST_SIZE = 15 * 1024 * 1024  # 15 MB (includes headers)

def validate_size(file_size: int):
    if file_size > MAX_FILE_SIZE:
        raise ValueError(f"File too large: {file_size} bytes (max {MAX_FILE_SIZE})")

# FastAPI example
from fastapi import UploadFile, HTTPException

@app.post("/upload")
async def upload_file(file: UploadFile):
    # Read in chunks to enforce limit
    contents = b""
    while chunk := await file.read(8192):
        contents += chunk
        if len(contents) > MAX_FILE_SIZE:
            raise HTTPException(413, "File too large")

    return await process_file(contents, file.filename)
```

### 6. Storage Location

Store outside webroot, serve through application:

```python
from pathlib import Path
import aiofiles

# Outside webroot - NOT /var/www/uploads
UPLOAD_DIR = Path("/var/app/uploads")
UPLOAD_DIR.mkdir(parents=True, exist_ok=True)

async def store_file(file_bytes: bytes, filename: str) -> str:
    """Store file and return ID for retrieval."""
    safe_name = sanitize_filename(filename)
    file_id = str(uuid.uuid4())

    # Store with ID-based path to prevent collisions
    file_path = UPLOAD_DIR / file_id[:2] / file_id[2:4] / f"{file_id}_{safe_name}"
    file_path.parent.mkdir(parents=True, exist_ok=True)

    async with aiofiles.open(file_path, 'wb') as f:
        await f.write(file_bytes)

    # Store metadata in database
    await db.files.insert({
        "id": file_id,
        "original_name": filename,
        "stored_name": safe_name,
        "path": str(file_path),
        "size": len(file_bytes),
    })

    return file_id
```

### 7. Serve Through Handler

```python
from fastapi import Response
from fastapi.responses import FileResponse

@app.get("/files/{file_id}")
async def get_file(file_id: str, current_user: User = Depends(get_current_user)):
    # Look up file
    file_record = await db.files.get(file_id)
    if not file_record:
        raise HTTPException(404)

    # Check user has access
    if not await user_can_access_file(current_user, file_record):
        raise HTTPException(403)

    # Serve with security headers
    return FileResponse(
        file_record["path"],
        filename=file_record["original_name"],
        headers={
            "Content-Disposition": f'attachment; filename="{file_record["original_name"]}"',
            "X-Content-Type-Options": "nosniff",
            "Content-Security-Policy": "default-src 'none'",
        }
    )
```

### 8. Image Reprocessing

Destroy embedded payloads by reprocessing images:

```python
from PIL import Image
import io

def sanitize_image(file_bytes: bytes, max_dimension: int = 4096) -> bytes:
    """Reprocess image to strip metadata and embedded content."""
    try:
        img = Image.open(io.BytesIO(file_bytes))

        # Convert to RGB (strips some payloads)
        if img.mode in ('RGBA', 'P'):
            img = img.convert('RGB')

        # Resize if too large
        if max(img.size) > max_dimension:
            img.thumbnail((max_dimension, max_dimension))

        # Re-encode (strips metadata, EXIF, embedded files)
        output = io.BytesIO()
        img.save(output, format='JPEG', quality=85)
        return output.getvalue()

    except Exception as e:
        raise ValueError(f"Invalid image: {e}")
```

### 9. Antivirus Scanning

```python
import clamd  # ClamAV client

async def scan_for_malware(file_bytes: bytes) -> bool:
    """Scan file with ClamAV. Returns True if clean."""
    try:
        cd = clamd.ClamdUnixSocket()
        result = cd.instream(io.BytesIO(file_bytes))
        status = result.get('stream', ('', ''))[0]
        return status == 'OK'
    except Exception as e:
        # Fail closed - reject if can't scan
        raise ValueError(f"Malware scan failed: {e}")

# Or use VirusTotal API for hash checking
async def check_virustotal(file_hash: str) -> bool:
    async with httpx.AsyncClient() as client:
        response = await client.get(
            f"https://www.virustotal.com/api/v3/files/{file_hash}",
            headers={"x-apikey": VT_API_KEY}
        )
        if response.status_code == 404:
            return True  # Not in database, unknown
        data = response.json()
        stats = data["data"]["attributes"]["last_analysis_stats"]
        return stats["malicious"] == 0
```

### 10. Zip Bomb Protection

```python
import zipfile

MAX_DECOMPRESSED_SIZE = 100 * 1024 * 1024  # 100 MB
MAX_FILES_IN_ZIP = 100
MAX_NESTING_DEPTH = 3

def safe_extract_zip(zip_bytes: bytes, extract_to: Path) -> list[Path]:
    """Extract zip with safety checks."""
    with zipfile.ZipFile(io.BytesIO(zip_bytes)) as zf:
        # Check total decompressed size
        total_size = sum(info.file_size for info in zf.infolist())
        if total_size > MAX_DECOMPRESSED_SIZE:
            raise ValueError(f"Zip bomb detected: {total_size} bytes decompressed")

        # Check file count
        if len(zf.infolist()) > MAX_FILES_IN_ZIP:
            raise ValueError("Too many files in zip")

        extracted = []
        for info in zf.infolist():
            # Skip directories
            if info.is_dir():
                continue

            # Check for path traversal
            target = (extract_to / info.filename).resolve()
            if not target.is_relative_to(extract_to):
                raise ValueError(f"Path traversal attempt: {info.filename}")

            # Check nesting depth
            if info.filename.count('/') > MAX_NESTING_DEPTH:
                raise ValueError("Zip nesting too deep")

            # Check for nested zips
            if info.filename.lower().endswith('.zip'):
                raise ValueError("Nested zips not allowed")

            # Extract
            zf.extract(info, extract_to)
            extracted.append(target)

        return extracted
```

## FastAPI Complete Example

```python
from fastapi import FastAPI, UploadFile, HTTPException, Depends

app = FastAPI()

@app.post("/upload")
async def upload_file(
    file: UploadFile,
    current_user: User = Depends(get_current_user)
):
    # 1. Validate extension
    ext = validate_extension(file.filename)

    # 2. Read with size limit
    contents = await read_with_limit(file, MAX_FILE_SIZE)

    # 3. Validate magic bytes
    validate_magic_bytes(contents, ext)

    # 4. Scan for malware
    if not await scan_for_malware(contents):
        raise HTTPException(400, "File failed security scan")

    # 5. Reprocess images
    if ext in {".png", ".jpg", ".jpeg"}:
        contents = sanitize_image(contents)

    # 6. Store securely
    file_id = await store_file(contents, file.filename, current_user.id)

    return {"file_id": file_id}
```

## Audit Checklist

- [ ] Is there an extension allowlist (not denylist)?
- [ ] Are magic bytes validated against expected type?
- [ ] Are filenames sanitized or regenerated?
- [ ] Are files stored outside webroot?
- [ ] Are files served through an authenticated handler?
- [ ] Are size limits enforced before full upload?
- [ ] Are images reprocessed to strip payloads?
- [ ] Is antivirus scanning in place?
- [ ] Are zips checked for bombs before extraction?
- [ ] Are security headers set when serving files?

## References

- OWASP File Upload Cheat Sheet
- ImageTragick (CVE-2016-3714)
- Zip Slip vulnerability

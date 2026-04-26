# Data Pipeline Patterns

Patterns for building robust, idempotent data pipelines with checkpointing and error handling.

## Table of Contents

1. [Batch Processing](#batch-processing)
2. [Checkpointing and Resumability](#checkpointing-and-resumability)
3. [Idempotency](#idempotency)
4. [Schema Validation](#schema-validation)
5. [Error Handling in Pipelines](#error-handling-in-pipelines)

## Batch Processing

Process large datasets in manageable batches.

### Basic Batch Pattern

```python
from collections.abc import Iterator, AsyncIterator

def batch_items(
    items: list[T],
    batch_size: int
) -> Iterator[list[T]]:
    """Split items into batches."""
    for i in range(0, len(items), batch_size):
        yield items[i:i + batch_size]

async def process_in_batches(
    items: list[Item],
    batch_size: int = 100
) -> ProcessResult:
    """Process items in batches."""
    processed = 0
    failed = 0

    for batch in batch_items(items, batch_size):
        try:
            await process_batch(batch)
            processed += len(batch)
        except Exception as e:
            logger.error(f"Batch processing failed: {e}")
            failed += len(batch)

    return ProcessResult(processed=processed, failed=failed)
```

### Async Batch Processing

```python
async def process_batches_concurrent(
    items: list[Item],
    batch_size: int = 100,
    max_concurrent: int = 5
) -> ProcessResult:
    """Process batches concurrently with limit."""
    semaphore = asyncio.Semaphore(max_concurrent)
    batches = list(batch_items(items, batch_size))

    async def process_with_semaphore(batch: list[Item]) -> int:
        async with semaphore:
            await process_batch(batch)
            return len(batch)

    processed = 0
    try:
        async with asyncio.TaskGroup() as tg:
            tasks = [
                tg.create_task(process_with_semaphore(batch))
                for batch in batches
            ]

        processed = sum(task.result() for task in tasks)
    except* Exception as eg:
        logger.error(f"Batch processing errors: {len(eg.exceptions)}")

    return ProcessResult(processed=processed)
```

## Checkpointing and Resumability

Save progress to resume from failures without reprocessing everything.

### Checkpoint State

```python
@dataclass(frozen=True)
class Checkpoint:
    pipeline_id: str
    last_processed_offset: int
    processed_count: int
    timestamp: datetime
    metadata: dict[str, Any] = field(default_factory=dict)

class CheckpointStore:
    """Abstract checkpoint storage."""

    async def save(self, checkpoint: Checkpoint) -> None:
        """Save checkpoint."""
        raise NotImplementedError

    async def load(self, pipeline_id: str) -> Checkpoint | None:
        """Load latest checkpoint."""
        raise NotImplementedError

    async def clear(self, pipeline_id: str) -> None:
        """Clear checkpoints for pipeline."""
        raise NotImplementedError
```

### File-Based Checkpoint Store

```python
import aiofiles

class FileCheckpointStore(CheckpointStore):
    """Store checkpoints in JSON files."""

    def __init__(self, checkpoint_dir: Path):
        self.checkpoint_dir = checkpoint_dir
        self.checkpoint_dir.mkdir(parents=True, exist_ok=True)

    def _checkpoint_path(self, pipeline_id: str) -> Path:
        return self.checkpoint_dir / f"{pipeline_id}.json"

    async def save(self, checkpoint: Checkpoint) -> None:
        """Save checkpoint to file."""
        path = self._checkpoint_path(checkpoint.pipeline_id)
        data = {
            "pipeline_id": checkpoint.pipeline_id,
            "last_processed_offset": checkpoint.last_processed_offset,
            "processed_count": checkpoint.processed_count,
            "timestamp": checkpoint.timestamp.isoformat(),
            "metadata": checkpoint.metadata
        }

        async with aiofiles.open(path, 'w') as f:
            await f.write(json.dumps(data, indent=2))

    async def load(self, pipeline_id: str) -> Checkpoint | None:
        """Load checkpoint from file."""
        path = self._checkpoint_path(pipeline_id)

        if not path.exists():
            return None

        async with aiofiles.open(path, 'r') as f:
            data = json.loads(await f.read())

        return Checkpoint(
            pipeline_id=data["pipeline_id"],
            last_processed_offset=data["last_processed_offset"],
            processed_count=data["processed_count"],
            timestamp=datetime.fromisoformat(data["timestamp"]),
            metadata=data.get("metadata", {})
        )
```

### Resumable Pipeline

```python
async def run_resumable_pipeline(
    pipeline_id: str,
    items: list[Item],
    checkpoint_store: CheckpointStore,
    batch_size: int = 100,
    checkpoint_interval: int = 10
) -> ProcessResult:
    """Run pipeline that can resume from checkpoint."""
    # Load checkpoint
    checkpoint = await checkpoint_store.load(pipeline_id)
    start_offset = checkpoint.last_processed_offset + 1 if checkpoint else 0

    logger.info(f"Starting pipeline from offset {start_offset}")

    processed = checkpoint.processed_count if checkpoint else 0

    for i, batch in enumerate(batch_items(items[start_offset:], batch_size)):
        current_offset = start_offset + (i * batch_size) + len(batch) - 1

        # Process batch
        await process_batch(batch)
        processed += len(batch)

        # Checkpoint periodically
        if (i + 1) % checkpoint_interval == 0:
            new_checkpoint = Checkpoint(
                pipeline_id=pipeline_id,
                last_processed_offset=current_offset,
                processed_count=processed,
                timestamp=datetime.now()
            )
            await checkpoint_store.save(new_checkpoint)
            logger.info(f"Checkpoint saved at offset {current_offset}")

    # Final checkpoint
    final_checkpoint = Checkpoint(
        pipeline_id=pipeline_id,
        last_processed_offset=len(items) - 1,
        processed_count=processed,
        timestamp=datetime.now(),
        metadata={"completed": True}
    )
    await checkpoint_store.save(final_checkpoint)

    return ProcessResult(processed=processed)
```

## Idempotency

Make operations safe to retry without causing duplicates or side effects.

### Idempotent Record Processing

```python
@dataclass(frozen=True)
class ProcessedRecord:
    record_id: str
    processed_at: datetime
    result: dict[str, Any]

class IdempotencyStore:
    """Track which records have been processed."""

    async def is_processed(self, record_id: str) -> bool:
        """Check if record was already processed."""
        raise NotImplementedError

    async def mark_processed(self, record: ProcessedRecord) -> None:
        """Mark record as processed."""
        raise NotImplementedError

async def process_record_idempotent(
    record: Record,
    store: IdempotencyStore
) -> ProcessedRecord | None:
    """Process record only if not already processed."""
    # Check if already processed
    if await store.is_processed(record.id):
        logger.info(f"Record {record.id} already processed, skipping")
        return None

    # Process record
    result = await process_record(record)

    # Mark as processed
    processed = ProcessedRecord(
        record_id=record.id,
        processed_at=datetime.now(),
        result=result
    )
    await store.mark_processed(processed)

    return processed
```

### Idempotency Key Pattern

```python
def generate_idempotency_key(*args: Any) -> str:
    """Generate idempotency key from arguments."""
    content = ":".join(str(arg) for arg in args)
    return hashlib.sha256(content.encode()).hexdigest()

async def idempotent_operation(
    operation_type: str,
    data: dict[str, Any],
    store: IdempotencyStore
) -> Result:
    """Execute operation idempotently."""
    # Generate idempotency key
    key = generate_idempotency_key(operation_type, json.dumps(data, sort_keys=True))

    # Check if already executed
    if await store.is_processed(key):
        # Return cached result
        cached = await store.get_result(key)
        return cached

    # Execute operation
    result = await execute_operation(operation_type, data)

    # Cache result
    await store.mark_processed(ProcessedRecord(
        record_id=key,
        processed_at=datetime.now(),
        result={"data": result}
    ))

    return result
```

## Schema Validation

Validate data at pipeline boundaries to fail fast.

### Pydantic Validation

```python
from pydantic import BaseModel, ValidationError, field_validator

class InputRecord(BaseModel):
    """Input data schema."""
    id: str
    email: str
    amount: Decimal
    timestamp: datetime

    @field_validator('email')
    @classmethod
    def validate_email(cls, v: str) -> str:
        """Validate email format."""
        if '@' not in v:
            raise ValueError('Invalid email format')
        return v.lower()

    @field_validator('amount')
    @classmethod
    def validate_amount(cls, v: Decimal) -> Decimal:
        """Validate amount is positive."""
        if v <= 0:
            raise ValueError('Amount must be positive')
        return v

async def validate_and_process(
    raw_data: dict[str, Any]
) -> ProcessResult:
    """Validate input before processing."""
    try:
        # Validate schema
        record = InputRecord.model_validate(raw_data)

        # Process validated record
        result = await process_record(record)
        return ProcessResult(success=True, result=result)

    except ValidationError as e:
        logger.error(f"Validation failed: {e}")
        return ProcessResult(success=False, error=str(e))
```

### Dead Letter Queue

```python
@dataclass(frozen=True)
class FailedRecord:
    original_data: dict[str, Any]
    error: str
    error_type: str
    timestamp: datetime
    retry_count: int = 0

class DeadLetterQueue:
    """Store failed records for later analysis."""

    async def add(self, record: FailedRecord) -> None:
        """Add failed record to queue."""
        raise NotImplementedError

    async def list_failures(self, limit: int = 100) -> list[FailedRecord]:
        """List recent failures."""
        raise NotImplementedError

async def process_with_dlq(
    raw_data: dict[str, Any],
    dlq: DeadLetterQueue
) -> ProcessResult:
    """Process record with dead letter queue for failures."""
    try:
        record = InputRecord.model_validate(raw_data)
        result = await process_record(record)
        return ProcessResult(success=True, result=result)

    except ValidationError as e:
        # Send to dead letter queue
        failed = FailedRecord(
            original_data=raw_data,
            error=str(e),
            error_type="validation_error",
            timestamp=datetime.now()
        )
        await dlq.add(failed)

        logger.error(f"Record sent to DLQ: {e}")
        return ProcessResult(success=False, error=str(e))
```

## Error Handling in Pipelines

Handle errors gracefully without failing entire pipeline.

### Partial Success Pattern

```python
@dataclass(frozen=True)
class BatchResult:
    successful: list[ProcessedItem]
    failed: list[tuple[Item, Exception]]

async def process_batch_with_errors(
    items: list[Item]
) -> BatchResult:
    """Process batch, collecting successes and failures separately."""
    successful: list[ProcessedItem] = []
    failed: list[tuple[Item, Exception]] = []

    for item in items:
        try:
            result = await process_item(item)
            successful.append(result)
        except Exception as e:
            logger.warning(f"Failed to process item {item.id}: {e}")
            failed.append((item, e))

    return BatchResult(successful=successful, failed=failed)
```

### Retry Failed Items

```python
async def process_with_retry(
    items: list[Item],
    max_retries: int = 3
) -> ProcessResult:
    """Process items with retry for failures."""
    failed_items = items
    attempt = 0
    all_successful: list[ProcessedItem] = []

    while failed_items and attempt < max_retries:
        attempt += 1
        logger.info(f"Attempt {attempt}: processing {len(failed_items)} items")

        # Process batch
        result = await process_batch_with_errors(failed_items)
        all_successful.extend(result.successful)

        # Retry only failed items
        failed_items = [item for item, _ in result.failed]

        if failed_items and attempt < max_retries:
            # Wait before retry
            await asyncio.sleep(2 ** attempt)

    return ProcessResult(
        processed=len(all_successful),
        failed=len(failed_items)
    )
```

### Progress Tracking

```python
class ProgressTracker:
    """Track pipeline progress."""

    def __init__(self, total: int):
        self.total = total
        self.processed = 0
        self.failed = 0
        self.start_time = datetime.now()

    def update(self, processed: int = 0, failed: int = 0) -> None:
        """Update progress counts."""
        self.processed += processed
        self.failed += failed

    @property
    def percent_complete(self) -> float:
        """Calculate completion percentage."""
        return (self.processed + self.failed) / self.total * 100

    @property
    def elapsed_time(self) -> timedelta:
        """Calculate elapsed time."""
        return datetime.now() - self.start_time

    @property
    def estimated_remaining(self) -> timedelta | None:
        """Estimate remaining time."""
        if self.processed == 0:
            return None

        rate = self.processed / self.elapsed_time.total_seconds()
        remaining_items = self.total - self.processed - self.failed
        remaining_seconds = remaining_items / rate

        return timedelta(seconds=remaining_seconds)

    def log_progress(self) -> None:
        """Log current progress."""
        logger.info(
            f"Progress: {self.percent_complete:.1f}% "
            f"({self.processed}/{self.total}) "
            f"- {self.failed} failed "
            f"- {self.elapsed_time} elapsed "
            f"- ~{self.estimated_remaining} remaining"
        )

# Usage
async def run_pipeline_with_progress(items: list[Item]) -> ProcessResult:
    """Run pipeline with progress tracking."""
    tracker = ProgressTracker(total=len(items))

    for batch in batch_items(items, batch_size=100):
        result = await process_batch_with_errors(batch)

        tracker.update(
            processed=len(result.successful),
            failed=len(result.failed)
        )
        tracker.log_progress()

    return ProcessResult(
        processed=tracker.processed,
        failed=tracker.failed
    )
```

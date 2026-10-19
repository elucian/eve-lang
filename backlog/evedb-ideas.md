1. Dual-Protocol Architecture (evedb)
Offering dual protocols is a high-leverage strategy if you want both standard ecosystem compatibility and maximum execution speed:

PostgreSQL Wire Protocol (Port): Use this strictly for external integration (BI tools, standard DB clients, ORMs, existing monitoring dashboards). It offloads the burden of writing custom connectors for standard developer tooling.

Native Eve Binary Protocol (IPC/TCP): Use this for internal node-to-node communication, native evedb worker pools, and client SDKs. Because it skips SQL string parsing, query planning translation, and Pg-specific authentication/parameter overhead, it will dramatically outperform the Pg protocol on raw throughput and serialization latency.

Comparing them provides a clean empirical benchmark for your documentation and compiler performance reports.

2. Can Anything Be Faster Than IPC for Zig-to-Zig Communication?
On a single machine, standard IPC (like Unix Domain Sockets or named pipes) involves kernel context switches and copying data between user space and kernel space.

If both Zig processes reside on the same host, you can bypass standard IPC entirely using these zero-copy mechanisms:

Shared Memory (POSIX Shared Memory / shm_open or Memory-Mapped Files)
How it works: Both Zig processes map a shared region of virtual memory using OS system calls (mmap).

The Speedup: Data written by one process is instantly visible to the other with zero copy operations and zero kernel round-trips.

ETL Application: The producer process writes Arrow IPC record batches directly into the shared memory ring buffer, and the consumer process (evedb) reads pointers to the memory blocks instantly. You only pass lightweight atomic index pointers (head/tail offsets) via a lock-free queue.

Lock-Free Ring Buffers over Shared Memory
Combine shared memory with atomic operations (std.atomic) to build a single-producer, single-consumer (SPSC) or multi-producer, multi-consumer (MPMC) ring buffer in Zig. This completely eliminates system call overhead during high-frequency data pipeline handoffs.

1. SQLite: Transactional & Control State (OLTP)
Purpose: Acts as the internal state engine for the Eve VM.

Use Cases: Storing job metadata, runtime configuration, pipeline state transitions, small lookup tables, and single-row operational writes.

Strengths: Minimal memory footprint, rapid single-row updates, zero configuration, and robust transactional safety.

2. DuckDB: High-Throughput Data Pipeline Execution (OLAP)
Purpose: Handles execution of large-scale data transformations within Eve ETL pipelines.

Use Cases: Aggregating large datasets, filtering millions of records, executing joins across external files (e.g., direct operations on .parquet or .csv), and preparing data for analytical destinations.

Strengths: High-speed analytical scans, vectorization, parallel execution, and minimal memory overhead during columnar scans.

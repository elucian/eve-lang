#!/bin/bash

# Create the main documentation directory
mkdir -p eve-docs

# Create the directory structure and empty files
cd eve-docs

# Core
mkdir -p core
touch core/syntax.md core/data-types.md core/control-structures.md

# Database
mkdir -p db/extensions
touch db/overview.md db/connection.md db/orm.md db/queries.md db/transactions.md
touch db/extensions/postgresql.md db/extensions/oracle.md db/extensions/mysql.md

# Network
mkdir -p net
touch net/overview.md net/http.md net/sockets.md

# Operating System
mkdir -p os
touch os/overview.md os/file-system.md os/processes.md

# Standard Library
mkdir -p std
touch std/collections.md std/strings.md std/math.md

# Main index file
touch index.md

echo "Eve documentation structure created successfully!"
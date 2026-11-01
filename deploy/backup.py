#!/usr/bin/env python3
"""Consistent, private SQLite backup with 14-day local retention."""
import datetime as dt
import os
from pathlib import Path
import sqlite3
os.umask(0o077)
root=Path('/var/lib/spare-room/backups'); root.mkdir(mode=0o700,exist_ok=True)
now=dt.datetime.now(dt.timezone.utc)
path=root/(now.strftime('%Y-%m-%d')+'.sqlite3')
with sqlite3.connect('file:/var/lib/spare-room/rooms.sqlite3?mode=ro',uri=True) as source, sqlite3.connect(path) as target:
    source.backup(target)
    if target.execute('PRAGMA integrity_check').fetchone()[0]!='ok': raise RuntimeError('Backup integrity check failed')
for old in root.glob('*.sqlite3'):
    if now.timestamp()-old.stat().st_mtime>14*86400: old.unlink()

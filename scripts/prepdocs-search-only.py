#!/usr/bin/env python3

import runpy
import sys
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[1]
UPSTREAM_BACKEND = REPO_ROOT / "upstream" / "app" / "backend"
sys.path.insert(0, str(UPSTREAM_BACKEND))

from prepdocslib.blobmanager import BlobManager


async def skip_document_upload(self: BlobManager, file: Any) -> None:
    return None


async def skip_image_upload(self: BlobManager, *args: Any, **kwargs: Any) -> None:
    return None


BlobManager.upload_blob = skip_document_upload
BlobManager.upload_document_image = skip_image_upload

runpy.run_path(str(UPSTREAM_BACKEND / "prepdocs.py"), run_name="__main__")
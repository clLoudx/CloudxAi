import sys
import os
# Ensure repo root is on sys.path so tests can import ai package
ROOT = os.path.dirname(os.path.dirname(__file__))
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)

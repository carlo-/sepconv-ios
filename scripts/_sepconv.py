
def _add_path():
    import os
    import sys
    _package_root_dir = os.path.join(os.path.dirname(__file__), '../../repo')
    if _package_root_dir not in sys.path:
        sys.path.append(_package_root_dir)


_add_path()

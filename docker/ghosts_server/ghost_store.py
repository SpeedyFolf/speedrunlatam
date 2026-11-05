from pathlib import Path
import re
import json

from binary_ghost import GhostFile

def get_valid_filename(name):
    """
    Return the given string converted to a string that can be used for a clean
    filename. Remove leading and trailing spaces; convert other spaces to
    underscores; and remove anything that is not an alphanumeric, dash,
    underscore, or dot.
    >>> get_valid_filename("john's portrait in 2004.jpg")
    'johns_portrait_in_2004.jpg'
    """
    s = str(name).strip().replace(" ", "_")
    s = re.sub(r"(?u)[^-\w.]", "", s)
    if s in {"", ".", ".."}:
        return None
    return s

class GhostStore:
    def __init__ (self, directory):
        self.directory = Path(directory)
        self.directory.mkdir(parents=True, exist_ok=True)

    def upload_ghost (self, ghost_name : str, ghost_data):
        ghost_file_name = get_valid_filename (ghost_name)
        if ghost_file_name is None:
            return

        ghost_file = GhostFile.from_json (json.loads(ghost_data)[0])
        ghost_file_bin = ghost_file.to_bin()
        with open(self.directory / (ghost_file_name), "wb") as f:
            f.write(ghost_file_bin)

    def download_ghost (self, ghost_name):
        ghost_file_name = get_valid_filename (ghost_name)
        if ghost_file_name is None:
            return

        with open(self.directory / (ghost_file_name), "rb") as f:
            ghost_file = GhostFile.from_bin (f.read())
            return json.dumps([ghost_file.to_json ()], separators=(',', ':'))

import sys
import os
import subprocess
import pathlib


sys.stderr.write(subprocess.check_output([
    "/usr/bin/pstree", "-a", "-l", "-A",
    "-s", str(os.getpid())
], text=True))

executable = pathlib.Path(sys.argv[1]).resolve()
args = ["toybox", "date"] + sys.argv[2:]

sys.stderr.write("%s: %s\n" % (executable, args))

os.execv(
    executable,
    args
)

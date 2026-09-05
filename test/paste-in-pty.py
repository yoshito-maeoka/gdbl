#!/usr/bin/env python3
"""Feeds a multi-line paste to gbdl through a real pty.

The bug this guards against only exists on a terminal: readline keeps a
bracketed paste in its own buffer and discards everything after the first
newline, so a pasted paragraph reached the model as one line. A pipe cannot
reproduce it, so the CLI is driven through a pty instead.

Usage: paste-in-pty.py <gbdl> <text-file>
       paste-in-pty.py --typed <gbdl>

`--typed` sends two lines the way a person types them, with a pause between,
to check that collecting a paste never reaches into the next line.

Prints the pty session to stdout; the caller inspects the stub's prompt log.
"""

import os
import pty
import select
import sys
import time


def drain(fd, seconds):
    out = b""
    end = time.time() + seconds
    while time.time() < end:
        ready, _, _ = select.select([fd], [], [], 0.1)
        if not ready:
            continue
        try:
            chunk = os.read(fd, 65536)
        except OSError:
            break
        if not chunk:
            break
        out += chunk
    return out.decode(errors="replace")


def finish(pid, fd):
    try:
        os.close(fd)
    except OSError:
        pass
    try:
        os.waitpid(pid, os.WNOHANG)
    except ChildProcessError:
        pass


def main():
    typed = sys.argv[1] == "--typed"
    if typed:
        gbdl, text = sys.argv[2], None
    else:
        gbdl, text = sys.argv[1], open(sys.argv[2]).read()

    pid, fd = pty.fork()
    if pid == 0:
        os.execvp(gbdl, [gbdl, "j"])

    banner = drain(fd, 2.0)

    if typed:
        # Two lines typed by hand. The pty has to be drained while waiting:
        # letting the master's buffer fill would block the CLI's own writes
        # and skew the timing this is meant to measure.
        os.write(fd, b"first line typed\r")
        session = drain(fd, 0.6)
        os.write(fd, b"second line typed\r")
        session += drain(fd, 1.0)
        os.write(fd, b"\x04")
        session += drain(fd, 1.0)
        finish(pid, fd)
        sys.stdout.write(banner + session)
        return

    # A terminal wraps a paste in ESC[200~ / ESC[201~ only when the application
    # has switched the mode on, so send what a real terminal would send. In
    # that mode the pasted newlines are inert, and the user presses Return
    # afterwards to submit.
    bracketed = "\x1b[?2004h" in banner
    payload = ("\x1b[200~" + text + "\x1b[201~") if bracketed else text

    # A terminal sends Return, not newline.
    os.write(fd, payload.replace("\n", "\r").encode())
    if bracketed:
        os.write(fd, b"\r")
    session = drain(fd, 3.0)

    os.write(fd, b"\x04")  # Ctrl-D
    session += drain(fd, 1.0)

    finish(pid, fd)
    sys.stdout.write(banner + session)


if __name__ == "__main__":
    main()

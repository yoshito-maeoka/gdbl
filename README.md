# gbdl
```
_____ ____  ____  ____    ____ ___  _ _____   ____  _____ _____ ____  _    
/  __//  _ \/  _ \/  _ \  /  __\\  \///  __/  /  _ \/  __//  __//  __\/ \   
| |  _| / \|| / \|| | \|  | | // \  / |  \    | | \||  \  |  \  |  \/|| |   
| |_//| \_/|| \_/|| |_/|  | |_\\ / /  |  /_   | |_/||  /_ |  /_ |  __/| |_/\
\____\\____/\____/\____/  \____//_/   \____\  \____/\____\\____\\_/   \____/
                                                                           
```

A DeepL-style translator for your terminal, running fully offline on a local
[Ollama](https://ollama.com) model.

`gbdl` is a thin wrapper around `ollama run {your-favorite-model}` that adds a fixed
translation prompt and an interactive read–translate–print loop. No API key,
no network, no data leaving your machine. gemma3:12b is the default model to use.

```console
$ gbdl j
gbdl: model: gemma3:12b - quit with Ctrl-D or Ctrl-C
[Japanese] > Guten Morgen, wie geht es dir?
おはよう、元気ですか？

[Japanese] > I worked a lot today.
今日はたくさん働いた。

[Japanese] >
```

## Features

- **Three target languages** — Japanese (default), English, German
- **Interactive loop** — type a line, get the translation, prompt returns
- **Auto-starts the Ollama server** if it is not already running
- **Result only** — the prompt asks the model to print nothing but the translation
- **Zero dependencies** beyond `bash` and `ollama`
- **Line editing** — arrow keys and history via readline

## Requirements

- [Ollama](https://ollama.com) on your `PATH`
- The `gemma3:12b` model (~8.1 GB on disk, ~10 GB RAM to run)

  ```sh
  ollama pull gemma3:12b
  ```

  If the model is missing, the first translation pulls it automatically.

- `bash` 4.0+ recommended. It still runs on the 3.2 that macOS ships, but 3.2
  has neither sub-second `read` timeouts nor `read -t 0`, so pastes are
  collected with a 1 s pause after every line and a paste whose last line has
  no trailing newline still loses that line. `brew install bash` avoids both.

## Install

Clone the repository and symlink the script into a directory on your `PATH`:

```sh
git clone https://github.com/yoshito-maeoka/gbdl.git
cd gbdl
ln -s "$PWD/gbdl" /usr/local/bin/gbdl     # or ~/.local/bin, /opt/homebrew/bin, ...
```

A symlink keeps the installed command in sync with the repository, so a
`git pull` is all it takes to update.

## Usage

```
gbdl [j|e|g]
```

| Option | Long form    | Target language        |
| ------ | ------------ | ---------------------- |
| `j`    | `--japanese` | Japanese (**default**) |
| `e`    | `--english`  | English                |
| `g`    | `--german`   | German                 |

Dashed short forms (`-j`, `-e`, `-g`) work too. `-h` / `--help` prints usage.

Type a line and press <kbd>Enter</kbd> to translate it. The prompt returns for
the next input.

Pasting works too, and the whole paste is translated. Input is handled a block
at a time, not a line at a time:

- Consecutive lines form one paragraph and are sent to the model together, so
  a hard-wrapped paragraph is translated as a paragraph rather than as a
  series of sentence fragments.
- A blank line ends the paragraph and is printed back as a blank line, so the
  shape of the original text is kept.

```console
$ gbdl j
[Japanese] > Der Bericht ist fertig. Ich habe alle Zahlen
noch einmal geprüft.

Bitte lies ihn vor dem Meeting.
レポートは完成しました。すべての数字を再度確認しました。

会議の前に読んでください。

[Japanese] >
```

| Key               | Action               |
| ----------------- | -------------------- |
| <kbd>Ctrl-D</kbd> | Quit (exit code 0)   |
| <kbd>Ctrl-C</kbd> | Quit (exit code 130) |

The source language is detected by the model — you can mix German, English,
Japanese and anything else `gemma3` understands in the same session.

## How it works

For every paragraph, `gbdl` calls `ollama run` once with this prompt:

```
please translate this text in {language}, and please print out only the result:
{text}
```

Two details of terminal input matter for pasted text:

- **Bracketed paste is turned off.** Readline keeps a bracketed paste in its
  own editing buffer and hands over only the first line, discarding the rest —
  a pasted paragraph would arrive as one line. With the mode off, the terminal
  delivers the paste as ordinary lines. `gbdl` does this through a generated
  inputrc that `$include`s your own, so your key bindings, arrow keys and
  history are unaffected. Readline only reads `INPUTRC` from the environment at
  start-up, so the script re-execs itself once to apply it.
- **The paste is collected before anything is translated.** A terminal's input
  buffer is about 1 KB; translating between lines would stall for seconds and
  the rest of a long paste would be dropped on the floor. `gbdl` reads the
  first line, drains whatever follows immediately, and only then starts
  translating. `ollama run` is given `/dev/null` as stdin so it cannot eat the
  input either.
- **The last line is collected even without a trailing newline.** Selecting a
  paragraph rarely picks up the newline after it, and a terminal in canonical
  mode holds an unterminated line back, so the last line would never be seen.
  For the moment it takes to collect the paste, `gbdl` switches the terminal
  to non-canonical mode, where those bytes are readable, and restores the
  previous settings straight afterwards.

The collection step only runs when input is already waiting the instant the
first line is accepted — true of a paste, never of someone typing, whose next
keystroke is still milliseconds away. Typed lines are therefore untouched:
each is its own block, translated immediately, with nothing swallowed from the
line that follows.

Before the first translation, `gbdl` checks the server with `ollama ps`. If it
is not answering, `ollama serve` is started in the background with STDOUT and
STDERR redirected to `/dev/null`, and `gbdl` waits (up to 30 s) until the
server is ready. The server is deliberately left running when `gbdl` exits, so
later sessions start instantly.

## Configuration

| Variable     | Default      | Description         |
| ------------ | ------------ | ------------------- |
| `GBDL_MODEL` | `gemma3:12b` | Ollama model to run |

Use a smaller model on a memory-constrained machine:

```sh
GBDL_MODEL=gemma3:4b gbdl e
```

## Exit codes

| Code  | Meaning                                           |
| ----- | ------------------------------------------------- |
| `0`   | Clean exit (<kbd>Ctrl-D</kbd> or `--help`)        |
| `2`   | Usage error — unknown or too many arguments       |
| `69`  | `ollama` not found, or the server failed to start |
| `130` | Interrupted with <kbd>Ctrl-C</kbd>                |

## Development

```
gbdl                    the CLI (a single bash script)
test/run-tests.sh       test suite
test/paste-in-pty.py    drives the CLI through a pty for the paste tests
```

Run the tests:

```sh
./test/run-tests.sh
```

The suite executes the real CLI against a stub `ollama` binary injected into
`PATH`, so it needs neither a downloaded model nor a running server and
finishes in a couple of seconds. It covers option parsing, the exact prompt
text, paragraph grouping, blank-line handling, EOF behaviour, error exit
codes, and the server auto-start logic.

Two cases need more than a pipe:

- The stub drains its stdin the way the real `ollama run` does, so the suite
  catches any regression that lets the model process swallow pending input.
- Multi-line paste is a terminal-only behaviour, so `test/paste-in-pty.py`
  runs the CLI under a pty and sends a paste the way a terminal would —
  including one with no trailing newline, and, with `--typed`, two lines typed
  at human speed to check that collecting a paste never reaches into the next
  line. It needs `python3`; those tests are skipped if that is missing.

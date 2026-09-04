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

- `bash` 3.2+ (the version shipped with macOS is fine)

## Install

Clone the repository and symlink the script into a directory on your `PATH`:

```sh
git clone https://github.com/<yoshito-maeoka>/gbdl.git
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
the next input. Blank lines are ignored.

| Key               | Action               |
| ----------------- | -------------------- |
| <kbd>Ctrl-D</kbd> | Quit (exit code 0)   |
| <kbd>Ctrl-C</kbd> | Quit (exit code 130) |

The source language is detected by the model — you can mix German, English,
Japanese and anything else `gemma3` understands in the same session.

## How it works

For every input line, `gbdl` calls `ollama run` once with this prompt:

```
please translate this text in {language}, and please print out only the result:
{text}
```

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
gbdl                 the CLI (a single bash script)
test/run-tests.sh    test suite
```

Run the tests:

```sh
./test/run-tests.sh
```

The suite executes the real CLI against a stub `ollama` binary injected into
`PATH`, so it needs neither a downloaded model nor a running server and
finishes in well under a second. It covers option parsing, the exact prompt
text, the re-prompt loop, blank-line handling, EOF behaviour, error exit
codes, and the server auto-start logic.
